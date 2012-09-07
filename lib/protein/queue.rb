# -*- encoding : utf-8 -*-
module Protein
  class Queue
    class << self
      delegate :config, :redis, :to => :Protein

      def blpop(timeout = 0)
        args = keys + [timeout]
        queue_key, item = redis.mblpop(*args)
        item[:queue] = extract_queue_name(queue_key) unless item.nil?
        yield(item) if block_given?
        item
      end
      alias_method :poll, :blpop

      def exists?(name)
        names.include?(name)
      end

      def names
        config.queues
      end

      def keys
        @keys ||= names.map {|name| queues[name].key}
      end

      def find(name)
        queues[name]
      end

      def default
        @default_queue ||= begin
          queue = find(:default)  
          raise 'Default queue is not configured' if queue.nil?
          queue
        end
      end

      def reset_all
        names.map {|name| queues[name].reset}
      end

      def key_prefix
        @key_prefix ||= config.queue_key
      end

      protected

      def queues
        @queues ||= Hash.new do |hash, name|
          hash[name] = new(name) if exists?(name)
        end
      end

      def extract_queue_name(key)
        key.sub(key_prefix + ':', '')
      end
    end

    delegate :config, :logger, :redis, :to => :Protein
    attr_reader :name

    def initialize(name)
      @name = name
      reset unless redis.list?(key)
    end

    def empty?
      length.zero?
    end

    def length
      redis.list_length(key).to_i
    end

    def push(item)
      redis.rpush(key, item)
    end

    def unshift(item)
      redis.lpush(key, item)
    end

    def shift
      item = redis.shift(key)
      yield(item) if block_given?
      item
    end

    def pop
      item = redis.pop(key)
      yield(item) if block_given?
      item
    end

    def blpop(timeout = 0)
      item = redis.blpop(key, timeout)
      yield(item) if block_given?
      item
    end
    alias_method :poll, :blpop

    def reset
      redis.delete(key)
    end

    def key
      @key ||= "#{key_prefix}:#{name}"
    end

    def key_prefix
      self.class.key_prefix
    end
  end

end