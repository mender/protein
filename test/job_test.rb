require 'test_helper'

describe Protein::Middleware::Chain do
  class ResetableJob < Protein::Job
    def self.reset_middleware
      @middleware = nil
    end
  end

  class MockQueueJob < Protein::Job
    def self.queue
      @queue ||= MiniTest::Mock.new
    end

    def queue
      @queue ||= MiniTest::Mock.new
    end
  end

  class MockRedisJob < Protein::Job
    def self.redis
      @redis ||= MiniTest::Mock.new
    end
  end

  class CustomWork
    def self.perform_args
      @perform_args
    end
    def self.perform(*args)
      @perform_args = args
    end
  end

  it 'should return id of job item' do
    job = Protein::Job.new(:id => 'cudtom_id')
    assert_equal 'cudtom_id', job.id
  end

  it 'should return nil if job item id is not specified' do
    job = Protein::Job.new({})
    assert_nil job.id
  end

  it 'should return class name of job item' do
    job = Protein::Job.new(:class => 'CustomWork')
    assert_equal 'CustomWork', job.klass_name
  end

  it 'should return nil if job item class name is not specified' do
    job = Protein::Job.new({})
    assert_nil job.klass_name
  end

  it 'should return args of job item' do
    job = Protein::Job.new(:args => ['args'])
    assert_equal ['args'], job.args
  end

  it 'should return nil if job item args are not specified' do
    job = Protein::Job.new({})
    assert_nil job.args
  end

  it 'should return class of job item' do
    job = Protein::Job.new(:class => 'CustomWork')
    assert_equal CustomWork, job.klass
  end

  it 'should raise NameError if job item has undefined class name' do
    job = Protein::Job.new(:class => 'UndefinedWork')
    assert_raises NameError do
      job.klass
    end
  end

  it 'should return job item created_at time as Time object' do
    created_at = Time.now
    job = Protein::Job.new(:created_at => created_at.to_f)
    assert_instance_of Time, job.created_at
    assert_equal created_at.to_f, job.created_at.to_f
  end

  it 'should call perform method of job item class and pass job item args to it' do
    job = Protein::Job.new(:class => 'CustomWork', :args => [:a, 'lot', {:of => :args}])
    assert_nil CustomWork.perform_args
    job.execute
    assert_equal [:a, 'lot', {:of => :args}], CustomWork.perform_args
  end

  describe '#rollback' do
    before do
      @job_item = {:class => 'RollbackMe', :args => []}
      @job = MockQueueJob.new(@job_item)
    end

    it 'should unshift job item' do
      @job.queue.expect(:unshift, nil, [@job_item])
      @job.rollback
      @job.queue.verify
    end

    it 'should return self' do
      @job.queue.expect(:unshift, nil, [@job_item])
      assert_equal @job, @job.rollback
    end
  end

  it 'should override to_s method' do
    created_at = Time.now
    job = Protein::Job.new(:class => 'CustomWork', :args => [42], :created_at => created_at, :id => 'item_id')
    assert_equal job.to_s, "id => item_id, name => CustomWork, created_at => #{created_at}, args => [42]"
  end

  it 'should override inspect method' do
    created_at = Time.now
    job = Protein::Job.new(:class => 'CustomWork', :args => [42], :created_at => created_at, :id => 'item_id')
    assert_equal job.inspect, "#<Protein::Job id => item_id, name => CustomWork, created_at => #{created_at}, args => [42]>"
  end

  describe '#middleware' do
    it 'default_middleware should return Middleware::Chain object with no items' do
      middleware = Protein::Job.default_middleware
      assert_instance_of Protein::Middleware::Chain, middleware
      assert_empty middleware.entries
    end

    it 'should yield with current middleware and return it' do
      ResetableJob.reset_middleware
      chain = Protein::Middleware::Chain.new
      ResetableJob.stub :default_middleware, chain do
        yield_with = nil
        result = ResetableJob.middleware { |m| yield_with = m }
        assert_equal result, chain
        assert_equal yield_with, chain
      end
    end
  end

  describe '#create' do
    before { @job = Protein::Job.create(SimpleWork, :a, 'lot', {:of => :args}) }

    it 'should raise ArgumentError if payload class name is blank' do
      assert_raises(ArgumentError) { Protein::Job.create(nil) }
      assert_raises(ArgumentError) { Protein::Job.create('') }
    end

    it 'should return hash with job params' do
      assert_instance_of Hash, @job
    end

    it 'should return id of new job' do
      assert @job.key?(:id)
    end

    it 'should return args of new job' do
      assert @job.key?(:args)
      assert_equal [:a, 'lot', {:of => :args}], @job[:args]
    end

    it 'should return payload class name' do
      assert @job.key?(:class)
      assert_equal 'SimpleWork', @job[:class]
    end

    it 'should return job created at time' do
      assert @job.key?(:created_at)
    end

    it 'should not return anything else' do
      assert_equal 4, @job.keys.count
    end

    it 'should use Time.now' do
      time = Time.now
      Time.stub :now, time do
        job = Protein::Job.create(SimpleWork)
        assert_equal job[:created_at], time.to_f
      end
    end

    it 'should generate job id with #next_id' do
      Protein::Job.stub :next_id, 'next_id' do
        job = Protein::Job.create(SimpleWork)
        assert_equal job[:id], 'next_id'
      end
    end

    it 'should use middleware stack' do
      recorder = []
      ResetableJob.reset_middleware
      ResetableJob.middleware.add MiddlewareRecorder, '0', recorder
      ResetableJob.create(SimpleWork, recorder)
      assert_equal %w(0 before 0 after), recorder.flatten
    end

    it 'should push item to the queue' do
      pushed = nil
      SimpleJob.reset_id
      SimpleJob.queue.stub :push, Proc.new{ |item| pushed = item } do
        SimpleJob.create(SimpleWork, 42)
        assert_instance_of Hash, pushed
        assert_equal 1, pushed[:id]
        assert_equal 'SimpleWork', pushed[:class]
        assert_equal [42], pushed[:args]
      end
    end
  end

  describe '#next' do
    it 'should call queue#poll method with queue_timeout configuration variable' do
      MockQueueJob.queue.expect(:poll, nil, [5])
      MockQueueJob.next
      MockQueueJob.queue.verify
    end

    it 'should return nil if queue is empty' do
      MockQueueJob.queue.expect(:poll, nil, [5])
      assert_nil MockQueueJob.next
      MockQueueJob.queue.verify
    end

    it 'should return self instance created from queue item' do
      queue_item = {:class => 'SimpleWork', :args => [42]}
      MockQueueJob.queue.expect(:poll, queue_item, [5])
      job = MockQueueJob.next
      assert_instance_of MockQueueJob, job
      assert_equal queue_item, job.instance_variable_get(:@job)
      MockQueueJob.queue.verify
    end
  end

  describe '#next_id' do
    it 'should return increasing sequence' do
      Protein::Job.reset_id
      seq = []
      5.times { seq << Protein::Job.next_id }
      assert_equal [1, 2, 3, 4, 5], seq
    end
  end

  describe '#reset_id' do
    it 'should set redis key to zero' do
      Protein::Job.next_id
      Protein::Job.reset_id
      assert_equal 1, Protein::Job.next_id
    end
  end

  describe '#delete_all' do
    it 'should clean queue and reset id sequence' do
      Protein::Job.create(SimpleWork)
      Protein::Job.delete_all
      assert Protein::Job.queue.empty?
      assert_equal 1, Protein::Job.next_id
    end
  end
end