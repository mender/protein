# -*- encoding : utf-8 -*-
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
        id = redis.blpop(key, timeout)
        if id.nil?
          raise Protein::TimeoutError.new("Worker lock #{name} timeout")
        end
        logger.debug "Worker lock #{name} acquired"
        
        block_given? ? with_release { yield(id) } : id
      end

      def release(id = nil)
        id ||= generate_id
        redis.push(key, id)
        logger.debug "Worker lock #{name} released"
        id
      end

      def get
        logger.debug "Worker lock #{name} get"
        redis.pop(key)
      end

      def reset
        logger.debug "Worker lock reset #{name}"
        clear
        feel
      end

      def feel
        value.times { redis.push(key, generate_id) }
      end

      def clear
        redis.delete(key)
      end

      def size
        redis.list_length(key)
      end
      alias_method :available, :size

      def acquired
        value - size
      end

      protected

      def generate_id
        SecureRandom.uuid
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