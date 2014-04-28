# -*- encoding : utf-8 -*-
require 'protein/uuid'

module Protein
  class Worker
    # BoundedSemaphore
    class Lock
      delegate :config, :logger, :redis, :to => :Protein
      attr_reader :name

      def initialize(name)
        @name  = name || 'common'
        reset #unless redis.list?(key)
      end

      def value
        config.concurrency
      end

      def acquire
        logger.debug "Worker lock #{name} waiting ..."
        id = redis.blpop_val(key, timeout)
        if id.nil?
          raise Protein::TimeoutError.new("Worker lock #{name} timeout")
        end
        logger.debug "Worker lock #{name} acquired"
        
        block_given? ? with_release { yield(id) } : id
      end

      def release(id = nil)
        id ||= generate_id
        redis.rpush(key, id)
        logger.debug "Worker lock #{name} released"
        id
      end

      def get
        logger.debug "Worker lock #{name} get"
        redis.rpop(key)
      end

      def reset
        logger.debug "Worker lock reset #{name}"
        clear
        feel
      end

      def feel
        value.times { redis.rpush(key, generate_id) }
      end

      def clear
        redis.del(key)
      end

      def size
        redis.llen(key)
      end
      alias_method :available, :size

      def acquired
        value - size
      end

      protected

      def generate_id
        Protein::Uuid.generate
      end

      def with_release
        if block_given?
          begin
            yield
          rescue => e
            release
            raise e
          end
        else
          nil
        end
      end

      def key
        @key ||= "#{name}:lock"
      end

      def timeout
        config.worker_lock_timeout
      end
    end
  end
end