# -*- encoding : utf-8 -*-
module Protein
  class Job
    class << self
      delegate :config, :logger, :redis, :to => :Protein

      def default_middleware
        Middleware::Chain.new
      end

      def middleware
        @middleware ||= default_middleware
        yield @middleware if block_given?
        @middleware
      end

      def create(klass, *args)
        if klass.to_s.empty?
          raise ArgumentError, "Jobs class is not specified"
        end

        queue = extract_queue!(args)
        raise ArgumentError, "Invalid queue name" if queue.nil?

        item = {
          :id         => next_id,
          :class      => klass.to_s,
          :args       => args,
          :created_at => Time.now.to_f
        }

        middleware.invoke(item) do
          #logger.debug("Create job #{item.inspect}")
          queue.push(item)
          item
        end
      end

      def next
        job = Queue.poll(config.queue_timeout)
        job.present? ? new(job) : nil
      end

      def delete_all
        #logger.debug("Delete all jobs")
        # TODO need sync
        Queue.reset_all
        reset_id
      end

      def next_id
        redis.incr(config.sequence_key)
      end

      def reset_id
        redis.zero(config.sequence_key)
      end

      protected

      def extract_queue_name!(args)
        options = args.last.is_a?(Hash) ? args.pop : {}
        name = options.delete(:queue)
        args.push(options) unless options.blank?
        name
      end

      def extract_queue!(args)
        queue_name = extract_queue_name!(args)
        queue_name ? Queue.find(queue_name) : Queue.default
      end
    end
    
    delegate :config, :logger, :to => :Protein
    attr_accessor :queue_name
    
    def initialize(job)  
      @job = job
      @queue_name = @job.delete(:queue)
    end

    def id
      @job[:id]
    end

    def klass
      @klass ||= job_classes[@job[:class]]
    end

    def klass_name
      @job[:class]
    end

    def args
      @job[:args]
    end

    def created_at
      @created_at ||= decode_time(@job[:created_at])
    end

    def execute
      klass.perform(*args)
    end

    def queue
      Queue.find(queue_name)
    end

    def rollback
      queue = self.queue
      if queue
        logger.debug "Rollback job #{@job.inspect}"
        queue.unshift(@job)
      else
        logger.debug "Rollback job #{@job.inspect}: queue is not specified, nothing to do"
      end
      self
    end

    def inspect
      "#<#{self.class.name} #{to_s}>"
    end

    def to_s
      @str ||= "id => #{id}, name => #{klass_name}, queue => #{queue_name}, created_at => #{created_at}, args => #{args.inspect}"
    end

    protected

    def decode_time(time)
      Time.at(time)
    end

    def job_classes
      @@_job_classes ||= Hash.new do |classes, name|
        classes[name] = constantize(name)
      end
    end

    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      args     = Module.method(:const_get).arity != 1 ? [false] : []
      names.each do |name|
        if constant.const_defined?(name, *args)
          constant = constant.const_get(name)
        else
          constant = constant.const_missing(name)
        end
      end
      constant
    end

  end
end
