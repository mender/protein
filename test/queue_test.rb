require 'test_helper'

describe Protein::Queue do
  class TestQueue < Protein::Queue
    def config
      @config ||= CustomConfig.new.tap do |config|
        config.queue_key = "test_queue"
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
    @queue = TestQueue.new
    @redis = @queue.redis
    @redis.delete(@queue.key)
  end

  it 'should read key from config' do
    assert_equal @queue.key, 'test_queue'
  end

  it 'should delete redis key when reset' do
    @redis.set(@queue.key, 'some_data')
    @queue.reset
    assert_nil @redis.get(@queue.key)
  end

  it 'should reset on initialize if key is not list' do
    @redis.set(@queue.key, 'some_data')
    TestQueue.new
    assert_nil @redis.get(@queue.key)
  end

  it 'should not reset on initialize if key is list' do
    @redis.push(@queue.key, 'some_data')
    TestQueue.new
    assert_equal ['some_data'], @redis.list(@queue.key)
  end

  it 'should return queue length' do
    5.times { @redis.push(@queue.key, 1) }
    assert_equal 5, @queue.length
  end

  it 'should be empty if list is blank' do
    assert_equal true, @queue.empty?
  end

  it 'should not be empty if list is not blank' do
    @redis.push(@queue.key, 1)
    assert_equal false, @queue.empty?
  end

  it 'should rpush new item to redis if pushed' do
    @redis.push(@queue.key, 'begin')
    @queue.push('some_data')
    assert_equal %w(begin some_data), @redis.list(@queue.key)
  end

  it 'should lpush new item to redis if unshift' do
    @redis.push(@queue.key, 'begin')
    @queue.unshift('some_data')
    assert_equal %w(some_data begin), @redis.list(@queue.key)
  end

  it 'should rpop item from redis if pop' do
    @redis.push(@queue.key, 'begin')
    @redis.push(@queue.key, 'end')
    assert_equal 'end', @queue.pop
  end

  it 'should lpop item from redis if shift' do
    @redis.push(@queue.key, 'begin')
    @redis.push(@queue.key, 'end')
    assert_equal 'begin', @queue.shift
  end

  describe '#blpop' do
    before do
      @queue.redis = @redis = MiniTest::Mock.new
    end

    it 'should call redis#blpop with specified timeout' do
      @redis.expect(:blpop, 'some_data', [@queue.key, 42])
      assert_equal 'some_data', @queue.blpop(42)
      @redis.verify
    end

    it 'should call redis#blpop with zero timeout if timeout is not specified' do
      @redis.expect(:blpop, 'some_data', [@queue.key, 0])
      assert_equal 'some_data',@queue.blpop
      @redis.verify
    end

    it 'should yield with selected item if block given' do
      @redis.expect(:blpop, 'some_data', [@queue.key, 0])
      yielded = nil
      @queue.blpop { |item| yielded = item }
      assert_equal 'some_data', yielded
    end

    it 'should return item if block given' do
      @redis.expect(:blpop, 'some_data', [@queue.key, 0])
      assert_equal 'some_data', @queue.blpop { |_| 42 }
    end
  end
end