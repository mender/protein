# -*- encoding : utf-8 -*-
require 'redis/namespace'

module Protein
  # Redis backend
  class Redis < Redis::Namespace
    delegate :logger, :config, :to => :Protein

    def initialize
      super(config.redis[:namespace], :redis => ::Redis.new(config.redis))
    rescue
      raise Protein::ConnectionError, $!.message
    end

    def delete(key)
      del(key)
    end

    def push(key, value)
      rpush(key, value)
    end

    def delete_keys(pattern = '*')
      keys(pattern).each { |key| del(key) }
    end

    def set?(key)
      type(key) == "set"
    end

    def hash?(key)
      type(key) == "hash"
    end

    def list?(key)
      type(key) == "list"
    end

    def hlength(key)
      hlen(key)
    end

    def list_length(key)
      llen(key)
    end

    def pop(key)
      rpop(key)
    end

    def blpop(key, timeout = 0)
      result = super(key, timeout)
      result && result[1]
    end

    def list(key)
      lrange key, 0, -1
    end

    def zero(key)
      set(key, 0)
    end

    def shift(key)
      lpop(key)
    end

    def increment(key)
      incr(key)
    end

    def reconnect
      redis.client.reconnect
    end

    attr_writer :redis
    alias :connection= :redis=
  end

end
