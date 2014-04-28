# -*- encoding : utf-8 -*-
require 'redis/namespace'
require 'protein/marshal'

module Protein
  class Redis < Redis::Namespace
    delegate :logger, :config, :to => :Protein

    attr_writer :redis
    alias :connection= :redis=

    def initialize
      ns    = config.redis[:namespace]
      redis = ::Redis.new(config.redis)
      super(ns, :redis => redis)
    rescue
      raise Protein::ConnectionError, $!.message
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

    def blpop_val(key, timeout = 0)
      result = blpop(key, timeout)
      result && result[1]
    end

    def zero(key)
      set(key, 0)
    end

    def reconnect
      redis.client.reconnect
    end

    # ==== serialization
    def blpop(*args)
      result = super
      result[1] = load(result[1]) if result
      result
    end

    def lpush(key, value)
      super(key, dump(value))
    end

    def rpush(key, value)
      super(key, dump(value))
    end

    def lpop(key)
      load(super)
    end

    def rpop(key)
      load(super)
    end

    def hset(key, field, value)
      super(key, field, dump(value))
    end

    def hget(key, field)
      load(super)
    end

    def set(key, value, expiry = 0)
      super(key, dump(value))
      expire(key, expiry) if expiry > 0
      value
    end

    def get(key)
      load(super)
    end

    def list(key)
      return nil unless list?(key)
      lrange(key, 0, -1).map{ |i| load(i) }
    end
    # === /serialization

    protected

    def dump(data)
      Protein::Marshal.dump(data)
    end

    def load(data)
      Protein::Marshal.load(data)
    end
  end

end
