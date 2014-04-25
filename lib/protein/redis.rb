# -*- encoding : utf-8 -*-
require 'redis'

module Protein
  class RedisMutex
    def self.acquire(redis, key, &block)
      timeout(60) { wait(redis, key) }
      redis.set(key, 1, 6)
      yield
    ensure
      redis.delete(key)
    end

    protected

    def self.wait(redis, key)
      while redis.exists?(key) do
        sleep 0.05
      end
    end
  end
  
  # Redis backend
  class Redis
    delegate :logger, :config, :to => :Protein

    def initialize
      redis
    rescue
      raise Protein::ConnectionError, $!.message
    end

    # increments the value for +key+ by 1 and returns the new value
    def increment(key)
      redis.incr _key(key)
    end

    # decrements the value for +key+ by 1 and returns the new value
    def decrement(key)
      redis.decr _key(key)
    end

    def zero(key)
      redis.set _key(key), 0
    end

    def keys(pattern = '*')
      redis.keys(_key(pattern)) || []
    end

    def zero_keys(pattern = '*')
      keys(pattern).each do |key|
        redis.set key, 0
      end
    end

    # tests whether +key+ exists or not
    def exists?(key)
      redis.exists _key(key)
    end

    # retrieve data from redis by +key+
    def get(key)
      u redis.get(_key(key))
    end
    alias [] get

    # retrieve plain data from redis by +key+
    def get!(key)
      redis.get(_key(key))
    end

    # set +value+ for +key+ and optionally expiration time
    def set(key, value, expiry = 0)
      redis.set _key(key), s(value)
      redis.expire _key(key), expiry if expiry > 0
      value
    end

    # set +value+ for +key+ only when it's missing in cache
    def set_if_not_exists(key, value, expiry)
      set key, value, expiry unless exists? key
      value
    end

    # shortcut for set without expiration
    def []=(key, value)
      return delete(key) if value.nil?

      set(key, value)
    end

    # remove +key+ from cache
    def delete(key)
      redis.del _key(key)
    end
    alias unset delete

    def delete_keys(pattern = '*')
      keys(pattern).each do |key|
        redis.del key
      end
    end

    # set expiration time for +key+
    def expire(key, expiry)
      redis.expire _key(key), expiry
    end

    # push new element at the head of the list
    def lpush(key, value)
      redis.lpush _key(key), s(value)
    end
    alias_method :unshift, :lpush

    # return first element of list and remove it
    def shift(key)
      u(redis.lpop _key(key))
    end

    # push new element at the end of the list
    def rpush(key, value)
      redis.rpush _key(key), s(value)
    end
    alias_method :push, :rpush

    # return last element of list and remove it
    def pop(key)
      u(redis.rpop _key(key))
    end

    # return LIST as ARRAY
    def list(key)
      return nil unless list?(key)

      result = []
      (redis.llen _key(key)).times do |idx|
        result << list_item(key, idx)
      end

      result
    end

    def list_item(key, idx)
      u(redis.lindex _key(key), idx)
    end

    # return list length of list
    def list_length(key)
      redis.llen(_key(key))
    end

    # is given +key+ is list
    def list?(key)
      redis.type(_key(key)) == "list"
    end

    # is given +key+ is set
    def set?(key)
      redis.type(_key(key)) == "set"
    end

    # is given +key+ is hash
    def hash?(key)
      redis.type(_key(key)) == "hash"
    end

    # is given +key+ is string
    def string?(key)
      redis.type(_key(key)) == "string"
    end

    def sadd(key, value)
      redis.sadd _key(key), s(value)
    end

    def sismember(key, value)
      redis.sismember _key(key), s(value)
    end

    def smembers(key)
      redis.smembers(_key(key)).map { |item| u(item) }
    end

    def srem(key, value)
      redis.srem _key(key), s(value)
    end

    def hset(key, field, value)
      redis.hset _key(key), field, s(value)
    end

    def hdel(key, field)
      redis.hdel _key(key), field
    end

    def hlength(key)
      redis.hlen _key(key)
    end

    def hexists(key, field)
      redis.hexists _key(key), field
    end

    def hget(key, field)
      u(redis.hget _key(key), field)
    end

    def hgetall(key)
      redis.hgetall(_key(key)).inject({}) do |result, (key, value)|
        result[key] = u(value)
        result
      end
    end

    def hkeys(key)
      redis.hkeys _key(key)
    end

    def blpop(key, timeout = 0)
      result = redis.blpop _key(key), timeout
      if result
        u(result[1])
      else
        nil
      end
    end

    def mblpop(*args)
      timeout = args.last.is_a?(Numeric) ? args.pop : 0
      keys = args.map{ |key| _key(key) }
      keys << timeout

      result = redis.blpop *keys
      if result
        [result[0].sub(key_prefix + ':', ''), u(result[1])]
      else
        nil
      end
    end

    # execute +block+ with pessimistic locking
    def synchronize(mutex_id, &block)
      mutex_key = "mutex:#{mutex_id}"

      RedisMutex.acquire(self, mutex_key, &block)
    end

    def redis
      @redis ||= ::Redis.new(config.redis)
    end
    alias :connection :redis

    attr_writer :redis
    alias :connection= :redis=

    def reconnect
      redis.client.reconnect
    end

    private

    def serialize(data)
      Marshal.dump data
    end
    alias_method :s, :serialize

    def unserialize(data)
      Marshal.load data
    rescue
      nil
    end
    alias_method :u, :unserialize

    def key_prefix
      @key_prefix ||= config.redis[:namespace]
    end

    def _key(key)
      "#{key_prefix}:#{key}"
    end
  end

end
