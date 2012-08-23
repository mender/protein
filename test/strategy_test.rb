require 'test_helper'

describe Protein::Strategy::Single do
  def with_job(&block)
    Protein::Job.stub :next, SimpleJob.new(SimpleWork), &block
  end

  def without_job(&block)
    Protein::Job.stub :next, nil, &block
  end

  before do
    @strategy = Protein::Strategy::Single.new
    Protein::Job.delete_all
  end

  describe '#loop' do
    it 'should start payload' do
      assert_call @strategy, :payload do
        @strategy.loop
      end
    end

    it 'should fire after_loop callbacks' do
      without_job do
        recorder = record_callbacks { @strategy.loop }
        assert_equal [:after_loop], recorder
      end
    end

    it 'should delete dead workers' do
      without_job do
        assert_call Protein::Worker, :delete_dead_workers do
          @strategy.loop
        end
      end
    end
  end

  describe '#payload' do
    it 'should not create worker without job' do
      without_job do
        assert_call_count 0, Protein::Worker, :create, :job do
          @strategy.payload
        end
      end
    end

    it 'should create new worker for each job' do
      with_job do
        assert_call_count 2, Protein::Worker, :create, :job do
          2.times { @strategy.payload }
        end
      end
    end

    it 'should execute job' do
      job = SimpleJob.new(SimpleWork)
      Protein.process.running = true
      Protein::Job.stub :next, job do
        assert_call job, :execute do
          @strategy.payload
        end
      end
    end

    it 'should return job to the queue if worker raises error' do
      job = SimpleJob.new(SimpleWork)
      Protein::Job.stub :next, job do
        @strategy.stub(:new_worker, Proc.new{raise RuntimeError}) do
          assert_call job, :rollback do
            @strategy.payload
          end
        end
      end
    end
  end
end

describe Protein::Strategy::Multi do
  before do
    @strategy = Protein::Strategy::Multi.new
    @worker = Protein::Worker.new
    @job = SimpleJob.new(SimpleWork)
    Protein::Job.delete_all
    @worker.process.running = true
  end

  describe '#payload' do
    it 'should start processing loop' do
      job = SimpleJob.new(SimpleWork)
      Protein.process.running = true
      Protein::Job.stub :next, job do
        done = false
        @strategy.stub(:start_thread, Proc.new{done = true}) do
          @strategy.payload
        end
        assert done
      end
    end
  end

  describe '#start_thread' do
    it 'should not execute job if worker process is stopped' do
      @worker.process.running = false
      assert_call_count 0, @job, :execute do
        @strategy.start_thread(@worker, @job)
      end
    end

    it 'should not execute job if worker is stale' do
      @worker.stub :stale?, true do
        assert_call_count 0, @job, :execute do
          @strategy.start_thread(@worker, @job)
        end
      end
    end

    class WorkRecorder
      def self.perform(id, recorder)
        recorder << id
      end
    end

    it 'should execute jobs while queue is not empty' do
      count = 0
      recorder = []
      job1 = SimpleJob.new(WorkRecorder, 1, recorder)
      job2 = SimpleJob.new(WorkRecorder, 2, recorder)
      @strategy.stub :next_job, Proc.new{result = [job2, nil][count]; count += 1; result} do
        @strategy.start_thread(@worker, job1)
        assert_equal [1,2], recorder
      end
    end
  end
end