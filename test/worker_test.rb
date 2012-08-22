require 'test_helper'

describe Protein::Worker do
  class TestWorker < Protein::Worker
    def self.reset_middleware
      @middleware = nil
    end
  end

  class TestWorker < Protein::Worker
    class TestCollection
      @@worker = nil
      def self.worker=(worker)
        @@worker = worker
      end

      def add
        yield @@worker || TestWorker.new
      end

      def delete(_)
      end
    end

    def self.collection(name)
      @collections ||= {}
      @collections[name] ||= TestCollection.new
    end
  end

  before do
    @simple_job = SimpleJob.new(SimpleWork)
  end

  describe '#middleware' do
    it 'default_middleware should return Middleware::Chain object with no items' do
      middleware = Protein::Worker.default_middleware
      assert_instance_of Protein::Middleware::Chain, middleware
    end

    it 'default_middleware should include WorkerMiddleware::AppName' do
      assert Protein::Worker.default_middleware.exists?(Protein::WorkerMiddleware::AppName)
    end

    it 'default_middleware should include WorkerMiddleware::LogJob' do
      assert Protein::Worker.default_middleware.exists?(Protein::WorkerMiddleware::LogJob)
    end

    it 'default_middleware should include WorkerMiddleware::LogWork' do
      assert Protein::Worker.default_middleware.exists?(Protein::WorkerMiddleware::LogWork)
    end

    it 'should yield with current middleware and return it' do
      TestWorker.reset_middleware
      chain = Protein::Middleware::Chain.new
      TestWorker.stub :default_middleware, chain do
        yield_with = nil
        result = TestWorker.middleware { |m| yield_with = m }
        assert_equal result, chain
        assert_equal yield_with, chain
      end
    end
  end

  describe '#execute_job' do
    it 'should return nil if job is nil' do
      assert_nil Protein::Worker.new.execute_job(nil)
    end

    it 'should use middleware stack' do
      worker = Protein::Worker.new
      assert_call Protein::Worker.middleware, :invoke, worker, @simple_job do
        worker.execute_job(@simple_job)
      end
    end

    it 'should call job execute method' do
      assert_call @simple_job, :execute do
        Protein::Worker.new.execute_job(@simple_job)
      end
    end

    it 'should change application name' do
      worker = Protein::Worker.new
      name = "job #{@simple_job.id}##{@simple_job.klass_name}"
      assert_call worker.process, :change_app_name, name do
        worker.execute_job(@simple_job)
      end
    end

    it 'should register job execution' do
      worker = Protein::Worker.new
      assert_call worker.item, :working_on, @simple_job do
        worker.execute_job(@simple_job)
      end
    end

    it 'should register job success' do
      worker = Protein::Worker.new
      assert_call worker.item, :success do
        worker.execute_job(@simple_job)
      end
    end

    it 'should register job failure' do
      worker = Protein::Worker.new
      job = SimpleJob.new(InvalidWork)
      assert_call worker.item, :fail do
        worker.execute_job(job)
      end
    end

    it 'should log job execution' do
      worker = Protein::Worker.new
      assert_call worker.logger, :info, "Executing job #{@simple_job.to_s}" do
        worker.execute_job(@simple_job)
      end
    end

    it 'should log job success' do
      worker = Protein::Worker.new
      assert_call worker.logger, :info, "Finished job #{@simple_job.id}##{@simple_job.klass_name}" do
        worker.execute_job(@simple_job)
      end
    end

    it 'should log job failure' do
      worker = Protein::Worker.new
      job = SimpleJob.new(InvalidWork)
      assert_call worker.logger, :error, "Failed job #{job.inspect}" do
        worker.execute_job(job)
      end
    end
  end

  describe '#create' do
    it 'should fork' do
      assert_call TestWorker.process, :fork do
        TestWorker.create(:job)
      end
    end

    describe 'in parent process' do
      def in_parent
        Kernel.stub(:fork, 42) do
          yield
        end
      end
    end

    describe 'in child process' do
      def in_child(&block)
        Kernel.stub(:fork, nil, &block)
      end

      before do
        @worker = Protein::Worker.new
        @worker.type = :job
        TestWorker::TestCollection.worker = @worker
      end

      it 'should register new worker' do
        in_child {
          assert_call TestWorker.collection(:job), :add do
            TestWorker.create(:job)
          end
        }
      end

      it 'should return new worker unless block given' do
        in_child { assert_kind_of Protein::Worker, TestWorker.create(:job) }
      end

      it 'should yield with new worker if block given' do
        in_child {
          yield_with = nil
          TestWorker.create(:job) { |w| yield_with = w }
          assert_equal @worker, yield_with
        }
      end

      it 'should call worker do method if block given' do
        in_child {
          assert_call @worker, :do do
            TestWorker.create(:job) {}
          end
        }
      end

      it 'should log unhandled exception' do
        in_child {
          e = RuntimeError.new 'unhandled error'
          assert_call @worker.logger, :error, e do
            TestWorker.create(:job) { raise e }
          end
        }
      end

      it 'should unregister worker' do
        in_child {
          assert_call TestWorker.collection(:job), :delete, @worker do
            TestWorker.create(:job)
          end
        }
      end

      it 'should unregister worker if exception raised' do
        in_child {
          assert_call TestWorker.collection(:job), :delete, @worker do
            TestWorker.create(:job) { raise RuntimeError }
          end
        }
      end

      it 'should exit' do
        in_child {
          assert_call @worker.process, :exit do
            TestWorker.create(:job)
          end
        }
      end

      it 'should exit if exception raised' do
        in_child {
          assert_call @worker.process, :exit do
            TestWorker.create(:job) { raise RuntimeError }
          end
        }
      end
    end
  end

  describe '#all' do
    before do
      Protein.redis.delete_keys
      Protein.process.running = true
      @collections = Protein::Worker::Collections.new
      @collection1 = @collections.create(:group1)
      @collection2 = @collections.create(:group2)
      @worker1 = @collection1.add
      @worker2 = @collection2.add
    end

    it 'should return workers from all registered collections' do
      assert_equal 2, Protein::Worker.all.count
    end

    it 'should return workers with registered ids' do
      ids = Protein::Worker.all.map { |w| w.id }
      assert_equal [@worker1.id, @worker2.id], ids
    end
  end

  describe '#delete_dead_workers' do
    before do
      Protein.redis.delete_keys
      Protein.process.running = true
      @collections = Protein::Worker::Collections.new
      @collection1 = @collections.create(:group1)
      @collection2 = @collections.create(:group2)
      @worker1 = @collection1.add
      @worker1.pid = 0
      @worker1.item.save
      @worker2 = @collection2.add
    end

    it 'should delete dead worker from its collection' do
      assert_equal 1, @collection1.count
      Protein::Worker.delete_dead_workers
      assert_equal 0, @collection1.count
    end

    it 'should log work' do
      assert_call Protein.logger, :info, "Delete dead worker [id: #{@worker1.id}, pid: #{@worker1.pid}] from collection group1" do
        Protein::Worker.delete_dead_workers
      end
    end
  end

  describe '#alive?' do
    it 'should return false if worker id is not specified' do
      refute Protein::Worker.new.alive?
    end

    it 'should return false if worker process does not exists' do
      worker = Protein::Worker.new
      worker.pid = 42
      worker.process.tools.stub :exists?, false do
        refute worker.alive?
      end
    end

    it 'should return true if worker process is running' do
      worker = Protein::Worker.new
      worker.pid = 42
      worker.process.tools.stub :exists?, true do
        assert worker.alive?
      end
    end
  end

  describe '#started?' do
    it 'should return false if worker id is not specified' do
      refute Protein::Worker.new.started?
    end

    it 'should return true if worker id is specified' do
      worker = Protein::Worker.new
      worker.pid = 0
      assert worker.started?
    end
  end

  describe '#dead?' do
    it 'should return false if worker id is not specified' do
      refute Protein::Worker.new.dead?
    end

    it 'should return true if worker process does not exists' do
      worker = Protein::Worker.new
      worker.pid = 42
      worker.process.tools.stub :exists?, false do
        assert worker.dead?
      end
    end

    it 'should return false if worker process is running' do
      worker = Protein::Worker.new
      worker.pid = 42
      worker.process.tools.stub :exists?, true do
        refute worker.dead?
      end
    end
  end

  describe '#terminated?' do
    it 'should return false if worker process is marked as running' do
      worker = Protein::Worker.new
      worker.process.stub :running?, true do
        refute worker.terminated?
      end
    end

    it 'should return true if worker process is marked as stopped' do
      worker = Protein::Worker.new
      worker.process.stub :running?, false do
        assert worker.terminated?
      end
    end
  end

  describe '#age' do
    it 'should return 0 if start time is not set' do
      assert 0, Protein::Worker.new.age
    end

    it 'should return time elapsed from the start' do
      start_time = Time.utc(2012, 1, 1)
      age = 3
      worker = Protein::Worker.new
      Time.stub(:now, start_time) { worker.start }
      Time.stub(:now, start_time + age) do
        assert age, worker.age
      end
    end
  end

  describe '#stale?' do
    it 'should return false for new worker' do
      refute Protein::Worker.new.stale?
    end

    it 'should return true if worker is old' do
      worker = Protein::Worker.new
      worker.stub :age, config.worker_live_time + 1 do
        assert worker.stale?
      end
    end

    it 'should return true if worker has a lot of jobs processed' do
      worker = Protein::Worker.new
      worker.stub :processed, config.worker_jobs_limit + 1 do
        assert worker.stale?
      end
    end

    it 'should return false if worker is young and fresh' do
      worker = Protein::Worker.new
      worker.stub :age, config.worker_live_time - 1 do
        worker.stub :processed, config.worker_jobs_limit - 1 do
          refute worker.stale?
        end
      end
    end
  end
end