# -*- encoding : utf-8 -*-
require 'protein/worker/lock'
require 'protein/uuid'

module Protein
  class Worker
    class Collection
      delegate :config, :logger, :redis, :process, :to => :Protein
      attr_reader :name

      def initialize(name)
        @name = name
        delete_all unless redis.hash?(key)
      end

      def build(id)
        Protein::Worker.new.tap do |worker|
          worker.item = CollectionItem.new(self, id)
          worker.type = self.name
          worker.hostname = config.hostname
          worker.created_at = Time.now
        end
      end

      def add
        get_lock do |id|
          worker = build(id)

          logger.debug("Add worker #{worker.id} to collection #{key}")
          worker.item.save

          block_given? ? yield(worker) : worker
        end
      end

      def delete(worker)
        unless include?(worker)
          logger.debug("Worker #{worker.id} was not found in collection #{key}")
          return false
        end
        release_lock do
          logger.debug("Delete worker #{worker.id} from collection #{key}")
          redis.hdel(key, worker.id)
          worker.freeze
        end
      rescue => e
        logger.error(e)
      end

      def update(id, item)
        logger.debug("Update item with id #{id} in collection #{key}")
        redis.hset(key, id, item)
      end

      def find(id)
        logger.debug("Get item with id #{id} from collection #{key}")
        redis.hget(key, id)
      end

      def include?(worker)
        return false unless valid_worker?(worker)
        logger.debug("Check presence of worker #{worker.id} in collection #{key}")
        redis.hexists(key, worker.id)
      end

      def workers
        logger.debug("Get all workers from collection #{key}")
        redis.hkeys(key).map do |id|
          build(id)
        end
      end

      def count
        logger.debug("Get length of workers collection #{key}")
        redis.hlength(key)
      end

      def dead_workers
        logger.debug("Get dead workers from collection #{key}")
        workers.select { |worker| worker.dead? }
      end

      def delete_all
        logger.debug("Delete workers collection #{key}")
        redis.delete(key) > 0
      end

      def lock
        @lock ||= create_lock
      end

      def key
        @key ||= "#{config.workers_key}:#{config.hostname}:#{name}"
      end

      protected

      def valid_worker?(worker)
        worker.id.present? && worker.item.present?
      end

      def create_lock
        lock = Protein::Worker::Lock.new(key)
        # если на момент запуска в системе существуют не остановленные worker'ы
        # принудительно уменьшим пул
        self.count.times {lock.get} 
        logger.debug "Worker lock with size #{lock.value} and [#{lock.available}] available locks created"
        lock
      end

      def get_lock
        lock.acquire do |id|
          # TODO избавиться
          # если дождались свободного места в пуле,
          # но во время ожидания пришла команда на остановку процесса
          unless process.running?
            logger.debug "Worker lock for collection #{key} return while termination"
            release_lock
            raise Protein::TerminationError
          end

          block_given? ? yield(id) : id
        end
      end

      def release_lock
        yield_result = block_given? ? yield : nil
        lock_result = lock.release
        block_given? ? yield_result : lock_result
      rescue => e
        logger.error(e)
      end
    end

    class CollectionItem
      delegate :config, :logger, :redis, :to => :Protein
      attr_reader :collection

      def self.dummy
        {
          :id => nil,
          :pid => nil,
          :type => nil,
          :status => :idle,
          :hostname => nil,
          :started_at => nil,
          :created_at => nil,

          :processed => 0,
          :completed => 0,
          :failed => 0,

          :job => nil,
          :job_started_at => nil
        }
      end

      def self.field_getter(*fields)
        fields.each do |field|
          define_method(field) do
            local[field]
          end
        end
      end

      def self.field_setter(*fields)
        fields.each do |field|
          define_method("#{field}=") do |value|
            logger.debug(">>>>#{field} => #{value} -> #{local.inspect}")
            local[field] = value
          end
        end
      end

      def self.field_accessor(*field)
        field_getter(*field)
        field_setter(*field)
      end

      field_accessor :pid, :type, :status, :hostname, :processed, :completed, :failed, :job

      def initialize(collection, id = nil)
        @collection = collection
        self.id = id
      end

      def id
        local[:id] ||= generate_id
      end

      def id=(id)
        @id = id
        local[:id] = id
      end

      def started_at
        decode_time(local[:started_at])
      end

      def started_at=(time)
        local[:started_at] = encode_time(time)
      end

      def created_at
        decode_time(local[:created_at])
      end

      def created_at=(time)
        local[:created_at] = encode_time(time)
      end

      def job_started_at
        decode_time(local[:job_started_at])
      end

      def job_started_at=(time)
        local[:job_started_at] = encode_time(time)
      end

      def working_on(job)
        self.status         = :busy
        self.job            = job.to_s
        self.job_started_at = Time.now
        save
      end

      def finished
        self.status         = :idle
        self.job            = nil
        self.job_started_at = nil
        self.processed      = self.processed + 1
        
        yield(self) if block_given?
        save
      end

      def success
        finished {|i| i.completed = i.completed + 1}
      end

      def fail
        finished {|i| i.failed = i.failed + 1}
      end

      def generate_id
        Protein::Uuid.generate
      end

      def to_h
        result = self.local
        result[:started_at] = started_at
        result[:created_at] = created_at
        result[:job_started_at] = job_started_at
        result
      end

      def save
        if registered?
          result = collection.update(id, local)
          @local = nil
          result
        else
          false
        end
      end

      protected

      def encode_time(time)
        time.present? ? time.to_f : time
      end

      def decode_time(time)
        time.present? ? Time.at(time) : time
      end

      def registered?
        @id.present? && collection.present?
      end

      def local
        @local ||= registered? && collection.find(@id) || self.class.dummy
      end
    end

    class CollectionItemStub < CollectionItem
      def initialize
        super(nil)
      end
    end

    class Collections
      delegate :config, :logger, :redis, :to => :Protein

      def initialize
        delete_all unless redis.set?(key)
      end

      def add(item)
        logger.debug("Add item #{item.name} to worker collection set #{key}")
        redis.sadd(key, item.name)
      end

      def delete(item)
        logger.debug("Delete item #{item.name} from worker collection set #{key}")
        redis.srem(key, item.name)
      end

      def create(name)
        item = build(name)
        add(item)
        item
      end

      def build(name)
        Collection.new(name)
      end

      def include?(item)
        logger.debug("Check existence of #{item.name} in worker collection set #{key}")
        redis.sismember(key, item.name)
      end

      def all
        logger.debug("Get all items from worker collection set #{key}")
        redis.smembers(key).map do |name|
          build(name)
        end
      end

      def delete_all
        logger.debug("Delete worker collection set #{key}")
        redis.delete(key) > 0
      end

      def key
        @key ||= "#{config.workers_key}:#{config.hostname}"
      end
    end
  end
end
