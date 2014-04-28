require 'test_helper'

describe Protein::Queue do
  class TestQueue < Protein::Queue
    def self.config
      @config ||= CustomConfig.new.tap do |config|
        config.queue_key = "test_queue"
        config.queues = [:q1, :q2]
      end
    end

    def self.redis=(redis)
      @redis = redis
    end

    def self.redis
      @redis || super
    end

    def config
      @config ||= CustomConfig.new.tap do |config|
        config.queue_key = "test_queue"
        config.queues = [:q1, :q2]
      end
    end

    def redis=(redis)
      @redis = redis
    end

    def redis
      @redis || super
    end
  end

  before do
    TestQueue.instance_variable_set :@queues, nil
    TestQueue.instance_variable_set :@default_queue, nil
    TestQueue.instance_variable_set :@key_prefix, nil

    @queue = TestQueue.new(:default)
    @redis = @queue.redis
    @redis.delete_keys
  end

  describe '.names' do
    it 'should read names from config' do
      assert_equal TestQueue.names, [:q1, :q2]
    end
  end

  describe '.keys' do
    it 'should prefix all queue names with queue key prefix' do
      assert_equal TestQueue.keys, ['test_queue:q1', 'test_queue:q2']
    end
  end

  describe '.find' do
    it 'should return queue with given name' do
      assert_instance_of TestQueue, TestQueue.find(:q1)
      assert_equal TestQueue.find(:q1).name, :q1
    end

    it 'should return nil if queue not found' do
      assert_nil TestQueue.find(:q3)
    end
  end

  describe '.default' do
    it 'should return default queue if configured' do
      config = CustomConfig.new.tap {|c| c.queues = [:default]}
      TestQueue.stub :config, config do
        assert_instance_of TestQueue, TestQueue.default
        assert_equal TestQueue.default.name, :default
      end
    end

    it 'should raise if not configured' do
      assert_raises RuntimeError do
        TestQueue.default
      end
    end
  end

  describe '.reset_all' do
    it 'should delete all items from all queues' do
      q1 = TestQueue.find :q1
      q2 = TestQueue.find :q2

      q1.push('some_data')
      q2.push('some_data')

      assert_equal q1.length, 1
      assert_equal q2.length, 1

      TestQueue.reset_all

      assert_equal q1.length, 0
      assert_equal q2.length, 0
    end
  end

  describe '.blpop' do
    before do
      TestQueue.redis = @redis = MiniTest::Mock.new
    end

    it 'should call redis#blpop with all queues and specified timeout' do
      @redis.expect(:blpop, ['key', {}], ['test_queue:q1', 'test_queue:q2', 42])
      TestQueue.blpop(42)
      @redis.verify
    end

    it 'should call redis#blpop with zero timeout if timeout is not specified' do
      @redis.expect(:blpop, ['key', {}], ['test_queue:q1', 'test_queue:q2', 0])
      TestQueue.blpop
      @redis.verify
    end

    it 'should yield with selected item if block given' do
      @redis.expect(:blpop, ['key', {:id => 42}], ['test_queue:q1', 'test_queue:q2', 0])
      yielded = nil
      TestQueue.blpop { |item| yielded = item }
      assert_instance_of Hash, yielded
      assert_equal 42, yielded[:id]
    end

    it 'should add queue name to item and return it' do
      @redis.expect(:blpop, ['key', {:id => 42}], ['test_queue:q1', 'test_queue:q2', 0])
      assert_equal({:id => 42, :queue => :key}, TestQueue.blpop)
    end

    it 'should delete queue key prefix from queue name' do
      @redis.expect(:blpop, ['test_queue:q1', {:id => 42}], ['test_queue:q1', 'test_queue:q2', 0])
      assert_equal({:id => 42, :queue => :q1}, TestQueue.blpop)
    end
  end

  it 'should read key from config' do
    assert_equal TestQueue.new(:default).key, 'test_queue:default'
  end

  it 'should delete redis key when reset' do
    @redis.set(@queue.key, 'some_data')
    @queue.reset
    assert_nil @redis.get(@queue.key)
  end

  it 'should reset on initialize if key is not list' do
    @redis.set(@queue.key, 'some_data')
    TestQueue.new(:default)
    assert_nil @redis.get(@queue.key)
  end

  it 'should not reset on initialize if key is list' do
    @redis.rpush(@queue.key, 'some_data')
    TestQueue.new(:default)
    assert_equal ['some_data'], @redis.list(@queue.key)
  end

  it 'should return queue length' do
    5.times { @redis.rpush(@queue.key, 1) }
    assert_equal 5, @queue.length
  end

  it 'should be empty if list is blank' do
    assert_equal true, @queue.empty?
  end

  it 'should not be empty if list is not blank' do
    @redis.rpush(@queue.key, 1)
    assert_equal false, @queue.empty?
  end

  it 'should rpush new item to redis if pushed' do
    @redis.rpush(@queue.key, 'begin')
    @queue.push('some_data')
    assert_equal %w(begin some_data), @redis.list(@queue.key)
  end

  it 'should lpush new item to redis if unshift' do
    @redis.rpush(@queue.key, 'begin')
    @queue.unshift('some_data')
    assert_equal %w(some_data begin), @redis.list(@queue.key)
  end

  it 'should rpop item from redis if pop' do
    @redis.rpush(@queue.key, 'begin')
    @redis.rpush(@queue.key, 'end')
    assert_equal 'end', @queue.pop
  end

  it 'should lpop item from redis if shift' do
    @redis.rpush(@queue.key, 'begin')
    @redis.rpush(@queue.key, 'end')
    assert_equal 'begin', @queue.shift
  end

  describe '#blpop' do
    before do
      @queue.redis = @redis = MiniTest::Mock.new
    end

    it 'should call redis#blpop with specified timeout' do
      @redis.expect(:blpop_val, 'some_data', [@queue.key, 42])
      assert_equal 'some_data', @queue.blpop(42)
      @redis.verify
    end

    it 'should call redis#blpop with zero timeout if timeout is not specified' do
      @redis.expect(:blpop_val, 'some_data', [@queue.key, 0])
      assert_equal 'some_data',@queue.blpop
      @redis.verify
    end

    it 'should yield with selected item if block given' do
      @redis.expect(:blpop_val, 'some_data', [@queue.key, 0])
      yielded = nil
      @queue.blpop { |item| yielded = item }
      assert_equal 'some_data', yielded
    end

    it 'should return item if block given' do
      @redis.expect(:blpop_val, 'some_data', [@queue.key, 0])
      assert_equal 'some_data', @queue.blpop { |_| 42 }
    end
  end
end