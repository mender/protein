require 'test_helper'

describe Protein::Worker::Lock do
  #class TestQueue < Protein::Queue
  #  def config
  #    @config ||= CustomConfig.new.tap do |config|
  #      config.queue_key = "test_queue"
  #    end
  #  end
  #
  #  def redis=(redis)
  #    @redis = redis
  #  end
  #
  #  def redis
  #    @redis || super
  #  end
  #end

  before do
    @lock = Protein::Worker::Lock.new('custom_lock')
    @redis = Protein.redis
    @key = @lock.send(:key)
    @redis.delete(@key)
  end

  it 'should generate redis key with name prefix' do
    assert_equal @lock.send(:key), 'custom_lock:lock'
  end

  it 'should read value from config.concurrency' do
    assert_equal 4, @lock.value
  end

  it 'should initialize with specified name' do
    assert_equal 'custom_lock', @lock.name
  end

  it 'should feel redis with ids and its count should be equal to concurrency value' do
    @lock.feel
    assert_equal 4, @redis.list_length(@key)
  end

  it 'should feel redis with valid ids' do
    @lock.feel
    @redis.list(@key).each do |item|
      assert_match /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, item
    end
  end

  it 'should feel redis with different ids' do
    @lock.feel
    assert_equal 4, @redis.list(@key).uniq.count
  end

  it 'should delete redis key when clear' do
    @redis.set(@key, 'some_data')
    @lock.clear
    assert_nil @redis.get(@key)
  end

  it 'should call clear and feel when reset' do
    clear = feel = false
    @lock.stub :feel, Proc.new{feel = true} do
      @lock.stub :clear, Proc.new{clear = true} do
        @lock.reset
      end
    end
    assert_equal true, clear
    assert_equal true, feel
  end

  it 'size should return redis list length' do
    2.times {@redis.push(@key, 1)}
    assert_equal 2, @lock.size
  end

  it 'acquired should return difference between value and size' do
    @redis.push(@key, 1)
    assert_equal 3, @lock.acquired
  end

  it 'should immediately return last lock when get' do
    @redis.push(@key, 'first')
    @redis.push(@key, 'last')
    assert_equal 'last', @lock.get
  end

  it 'should push specified id when release' do
    @redis.push(@key, 'first')
    @lock.release('released_id')
    assert_equal ['first', 'released_id'], @redis.list(@key)
  end

  it 'should push new id when release and id is not specified' do
    @redis.push(@key, 'first')
    @lock.stub :generate_id, 'generated_id' do
      @lock.release
    end
    assert_equal ['first', 'generated_id'], @redis.list(@key)
  end

  describe '#acquire' do
    class TestLock < Protein::Worker::Lock
      def reset
      end

      def release
        @released = true
      end

      def released?
        !!@released
      end

      def redis=(redis)
        @redis = redis
      end

      def redis
        @redis || super
      end
    end

    class CustomLockError < StandardError; end

    before do
      @lock = TestLock.new('custom_lock')
      @lock.redis = @redis = MiniTest::Mock.new
    end

    it 'should call redis#blpop with worker_lock_timeout configuration value' do
      @redis.expect(:blpop, 'some_data', [@key, 5])
      assert_equal 'some_data', @lock.acquire
      @redis.verify
    end

    it 'should raise Protein::TimeoutError when timeout reached' do
      @redis.expect(:blpop, nil, [@key, 5])
      assert_raises Protein::TimeoutError do
        @lock.acquire
      end
    end

    it 'should return lock id if block is not specified' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      assert_equal 'lock_id', @lock.acquire
    end

    it 'should yield with lock id if block given' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      yielded = nil
      @lock.acquire { |id| yielded = id }
      assert_equal 'lock_id', yielded
    end

    it 'should return block value if block given' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      value = @lock.acquire { |_| 42 }
      assert_equal 42, value
    end

    it 'should not release lock if block is not specified' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      assert_equal false, @lock.released?
      @lock.acquire
      assert_equal false, @lock.released?
    end

    it 'should not release lock if block given' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      assert_equal false, @lock.released?
      @lock.acquire { }
      assert_equal false, @lock.released?
    end

    it 'should release lock if exception raised' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      assert_equal false, @lock.released?
      @lock.acquire { |_| raise CustomLockError } rescue nil
      assert_equal true, @lock.released?
    end

    it 'should proxy exception if raised' do
      @redis.expect(:blpop, 'lock_id', [@key, 5])
      assert_raises CustomLockError do
        @lock.acquire { |_| raise CustomLockError }
      end
    end
  end
end