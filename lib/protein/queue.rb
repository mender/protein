# -*- encoding : utf-8 -*-
module Protein
  class Queue
    delegate :config, :logger, :redis, :to => :Protein

    def initialize
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
      @key ||= config.queue_key
    end
  end

end