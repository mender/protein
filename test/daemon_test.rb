require 'test_helper'

describe Protein::Daemon do
  class TestStrategy

  end

  class TestDaemon < Protein::Daemon
    def loop
      2.times {yield}
    end

    def sleep(_)
    end

    def strategy
      @strategy ||= (Class.new {
        def loop
        end
      }).new
    end

    def exception_handling
      yield
    end
  end

  before do
    @daemon = TestDaemon.new
    Protein.redis.delete_keys
  end

  describe '#delay' do
    it 'should use main_loop_delay config variable' do
      assert_call @daemon.config, :main_loop_delay do
        @daemon.delay
      end
    end

    it 'should return main_loop_delay config variable' do
      @daemon.config.stub :main_loop_delay, 42 do
        assert_equal 42, @daemon.delay
      end
    end
  end

  describe '#run' do
    it 'should set daemon pid' do
      @daemon.process.stub :pid, 42 do
        assert_call @daemon.send(:_pid), :set, 42 do
          @daemon.run
        end
      end
    end

    it 'should delete daemon pid' do
      assert_call @daemon.send(:_pid), :del do
        @daemon.run
      end
    end

    it 'should unregister dead daemon' do
      @daemon.stub :dead?, true do
        assert_call @daemon, :unregister do
          @daemon.run
        end
      end
    end

    it 'should log dead daemon existence' do
      @daemon.stub :dead?, true do
        @daemon.send(:_pid).set(42)
        assert_call @daemon.logger, :warn, "Dead daemon detected: process with pid 42 not found" do
          @daemon.run
        end
      end
    end

    it 'should mark process as started' do
      assert_call @daemon.process, :startup do
        @daemon.run
      end
    end

    it 'should trap signals' do
      assert_call @daemon.process, :trap_signals do
        @daemon.run
      end
    end

    it 'should change application name' do
      assert_call @daemon.process, :change_app_name, 'daemon' do
        @daemon.run
      end
    end

    it 'should log self info' do
      info_string = ''
      @daemon.stub :pid, ::Process.pid do
        @daemon.stub :alive?, true do
          info_string = @daemon.to_s
        end
      end

      assert_call @daemon.logger, :info, "Daemon started [#{info_string}]" do
        @daemon.run
      end
    end

    it 'should close logger' do
      assert_call @daemon.logger, :close do
        @daemon.run
      end
    end

    it 'should run payload in main loop' do
      assert_call_count 2, @daemon.strategy, :loop do
        @daemon.run
      end
    end

    it 'should sleep in main loop' do
      assert_call_count 2, @daemon, :sleep, config.main_loop_delay do
        @daemon.run
      end
    end

    it 'should flush logger in main loop' do
      assert_call_count 3, @daemon.logger, :flush do
        @daemon.run
      end
    end

    it 'should exit main loop if process is marked as stopped' do
      @daemon.process.stub :running?, false do
        assert_call_count 0, @daemon, :sleep, config.main_loop_delay do
          @daemon.run
        end
      end
    end

    it 'should exit immediately if another daemon is started' do
      @daemon.stub :dead?, false do
        @daemon.send(:_pid).set(42)
        assert_call_count 0, @daemon.strategy, :loop do
          @daemon.run
        end
      end
    end

    it 'should return nil if another daemon is started' do
      @daemon.stub :dead?, false do
        @daemon.send(:_pid).set(42)
        assert_nil @daemon.run
      end
    end

    it 'should log if another daemon is started' do
      @daemon.stub :dead?, false do
        @daemon.send(:_pid).set(42)
        assert_call @daemon.logger, :info, "Another daemon with pid 42 is already running" do
          @daemon.run
        end
      end
    end
  end

  describe '#strategy' do
    class Protein::Strategy::Custom
    end

    it 'should use config strategy variable' do
      config.stub :strategy, :custom do
        assert_instance_of Protein::Strategy::Custom, Protein::Daemon.new.strategy
      end
    end
  end

  describe '#exception_handling' do
    it 'should catch exceptions' do
      caught = true
      Protein::Daemon.new.send(:exception_handling) { raise RuntimeError } rescue caught = false
      assert caught
    end

    it 'should log abnormal termination' do
      assert_call @daemon.logger, :error, "Abnormal termination." do
        Protein::Daemon.new.send(:exception_handling) { raise RuntimeError } rescue nil
      end
    end

    it 'should return nil' do
      result = Protein::Daemon.new.send(:exception_handling) { raise RuntimeError } rescue 'fuck!!!'
      assert_nil result
    end
  end

  describe '#run_in_background' do
    it 'should fork' do
      assert_call @daemon.process, :fork do
        @daemon.run_in_background
      end
    end

    it 'should run daemon in child process' do
      Kernel.stub(:fork, nil) do
        assert_call @daemon, :run do
          @daemon.run_in_background
        end
      end
    end

    it 'should return daemon pid in parent process' do
      allow_forks do
        Kernel.stub(:fork, 42) do
          assert_equal 42, @daemon.run_in_background
        end
      end
    end

    it 'should not run daemon in parent process' do
      allow_forks do
        Kernel.stub(:fork, 42) do
          assert_call_count 0, @daemon, :run do
            @daemon.run_in_background
          end
        end
      end
    end
  end
end