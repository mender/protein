# -*- encoding : utf-8 -*-
require 'protein/worker/collection'
require 'protein/middleware/chain'

module Protein
  class Worker
    class << self
      delegate :config, :logger, :process, :to => :Protein

      def default_middleware
        Middleware::Chain.new do |m|
          m.add WorkerMiddleware::AppName
          m.add WorkerMiddleware::LogJob
          m.add WorkerMiddleware::LogWork
        end
      end

      def middleware
        @middleware ||= default_middleware
        yield @middleware if block_given?
        @middleware
      end

      def create(type, &block)
        collection(type).add do |worker|
          process.fork do
            begin
              if block_given?
                worker.do(&block)
              else
                worker
              end
            rescue => e
              logger.error "Unhandled exception"
              logger.error e
            ensure
              safe_delete(worker)
              process.exit
            end
          end
        end
      end

      def all
        collection_set.all.inject([]) do |result, collection|
          result += collection.workers
          result
        end
      end

      def delete_dead_workers
        collection_set.all.each do |collection|
          collection.dead_workers.each do |worker|
            worker_info = "id: #{worker.id}, pid: #{worker.pid}"
            logger.info "Delete dead worker [#{worker_info}] from collection #{collection.name}"
            collection.delete(worker)
          end
        end
        nil
      end

      def item_getter(*names)
        delegate(*names, :to => :item)
      end

      def item_setter(*names)
        names = names.map { |name| "#{name}=" }
        delegate(*names, :to => :item)
      end

      def item_accessor(*names)
        item_getter(*names)
        item_setter(*names)
      end

      protected

      def safe_delete(worker)
        collection(worker.type).delete(worker)
      rescue => e
        logger.error(e)
      end

      def collection(type)
        @collections ||= Hash.new do |hash, name|
          hash[name] = collection_set.create(name)
        end
        @collections[type]
      end

      def collection_set
        @collection_set ||= Protein::Worker::Collections.new
      end
    end

    delegate :config, :logger, :process, :to => :Protein

    item_accessor :id, :type, :status, :hostname, :started_at, :created_at
    item_accessor :processed, :completed, :failed
    item_accessor :job, :job_started_at
    item_setter   :pid

    def do
      start
      process.trap_signals do
        process.change_app_name("worker #{self.status}") do
          yield(self)
        end
      end
    end

    def execute_job(job)
      return if job.nil?

      self.class.middleware.invoke(self, job) do
        job.execute
      end
    rescue => e
      logger.error e
    end

    def item=(item)
      @item = item
    end

    def item
      @item ||= Protein::Worker::CollectionItemStub.new
    end

    def info
      item.to_h.merge(:status => status_message)
    end

    def status_message
      status = self.status
      status = 'not started' unless started?
      status = 'dead' if dead?
      status
    end

    def real_pid
      process.pid
    end

    def pid
      item.pid
    end

    def dead?
      started? && !process.tools.exists?(pid)
    end

    def alive?
      started? && process.tools.exists?(pid)
    end

    def started?
      pid.present?
    end

    def terminated?
      !process.running?
    end

    def stale?
      (processed >= jobs_limit) || (age >= live_time)
    end

    def jobs_limit
      @@jobs_limit ||= config.worker_jobs_limit
    end

    def live_time
      @@live_time ||= config.worker_live_time
    end

    def age
      started_at.present? ? Time.now - started_at : 0
    end

    def start
      self.started_at = Time.now
      self.pid        = real_pid
      item.save
    end

  end

  module WorkerMiddleware
    class AppName
      def call(worker, job, &block)
        name = "job #{job.id}##{job.klass_name}"
        worker.process.change_app_name(name, &block)
      end
    end

    class LogJob
      def call(worker, job)
        worker.logger.info "Executing job #{job.to_s}"
        result = yield
        worker.logger.info "Finished job #{job.id}##{job.klass_name}"
        result
      rescue => e
        worker.logger.error "Failed job #{job.inspect}"
        raise e
      end
    end

    class LogWork
      def call(worker, job)
        worker.item.working_on(job)
        result = yield
        worker.item.success
        result
      rescue => e
        worker.item.fail
        raise e
      end
    end
  end
end
