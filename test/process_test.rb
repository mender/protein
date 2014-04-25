require 'test_helper'

describe Protein::Process do
  class TestProcess < Protein::Process
    def self.config
      @config ||= CustomConfig.new
    end

    def config
      self.class.config
    end

    def logger
      @logger || super
    end

    def logger=(logger)
      @logger = logger
    end

    def redis
      @redis || super
    end

    def redis=(redis)
      @redis = redis
    end
  end

  before do
    @process = TestProcess.new
  end

  describe '#initialize' do
    it 'should use can_fork config variable' do
      TestProcess.config.can_fork = false
      assert_equal false, TestProcess.new.can_fork
      TestProcess.config.can_fork = true
      assert_equal true, TestProcess.new.can_fork
    end

    it 'should not be running' do
      assert_equal false, Protein::Process.new.running
    end
  end

  describe '#running?' do
    it 'should be true if running' do
      @process.running = true
      assert_equal true, @process.running?
    end

    it 'should be false if not running' do
      @process.running = false
      assert_equal false, @process.running?
    end
  end

  describe '#can_fork?' do
    it 'should be true if can fork' do
      @process.can_fork = true
      assert_equal true, @process.can_fork?
    end

    it 'should be false if can\'t fork' do
      @process.can_fork = false
      assert_equal false, @process.can_fork?
    end
  end

  describe '#startup' do
    it 'should mark process as running' do
      @process.startup
      assert_equal true, @process.running?
    end

    it 'should set sync mode for stdout' do
      $stdout.sync = false
      @process.startup
      assert_equal true, $stdout.sync
    end

    if GC.respond_to?(:copy_on_write_friendly=)
      it 'should enable gc optimization' do
        assert_call GC, :copy_on_write_friendly=, true do
          @process.startup
        end
      end
    end
  end

  it 'should not be running if stopped' do
    @process.running = true
    @process.stop
    assert_equal false, @process.running?
  end

  it 'should return current process pid' do
    assert_equal ::Process.pid, @process.pid
  end

  describe '#change_app_name' do
    it 'should correctly change process name' do
      name = $0
      @process.change_app_name 'worker'
      assert_equal 'Protein: worker', $0
      $0 = name
    end

    it 'should change and restore process name if block given' do
      name = $0
      @process.change_app_name('worker') do
        assert_equal 'Protein: worker', $0
      end
      assert_equal name, $0
    end

    it 'should restore process name if exception raised' do
      name = $0
      @process.change_app_name('worker') { raise RuntimeError } rescue nil
      assert_equal name, $0
    end
  end

  describe '#reconnect' do
    it 'should reopen logger' do
      @process.logger = MiniTest::Mock.new
      @process.logger.expect(:reopen, nil)
      @process.reconnect
      @process.logger.verify
    end

    it 'should reconnect to redis' do
      @process.redis = MiniTest::Mock.new
      @process.redis.expect(:reconnect, nil)
      @process.reconnect
      @process.redis.verify
    end
  end

  describe '#exit' do
    it 'should exit from current process' do
      @process.exit
      refute_nil @process.exit_flag
    end

    it 'should fire before_exit callbacks' do
      recorder = record_callbacks { @process.exit }
      assert_equal [:before_exit], recorder
    end

    it 'should close logger' do
      assert_call(@process.logger, :close) {
        @process.exit
      }
    end

    it 'should exit from current process if callback raises exception' do
      raise_in_callback(:before_exit, RuntimeError) do
        @process.exit
      end rescue nil
      refute_nil @process.exit_flag
    end

    it 'should close logger if callback raises exception' do
      assert_call(@process.logger, :close) {
        raise_in_callback(:before_exit, RuntimeError) { @process.exit } rescue nil
      }
    end

    it 'should exit from current process if logger raises exception' do
      @process.logger.stub(:close, Proc.new{raise RuntimeError}) do
        @process.exit
      end
      refute_nil @process.exit_flag
    end
  end

  it 'should have tools' do
    TestProcess.config.process_term_timeout = 10
    TestProcess.config.process_kill_timeout = 20
    assert_instance_of Protein::ProcessTools, @process.tools
    assert_equal @process.logger, @process.tools.logger
    assert_equal 10, @process.tools.term_timeout
    assert_equal 20, @process.tools.kill_timeout
  end

  it 'should have signals' do
    assert_instance_of Protein::ProcessSignals, @process.signals
    assert_equal @process.logger, @process.signals.logger
  end

  describe '#trap_signals' do
    def assert_trap_signal(*signals)
      recorder = []
      @process.signals.stub :trap, Proc.new{|signal| recorder << signal} do
        yield
      end
      assert_equal recorder, signals
    end

    def assert_release_signal(*signals)
      recorder = []
      @process.signals.stub :release, Proc.new{|signal| recorder << signal} do
        yield
      end
      assert_equal recorder, signals
    end

    it 'should trap TERM, INT and HUP signals' do
      assert_trap_signal 'TERM', 'INT', 'HUP' do
        @process.trap_signals
      end
    end

    it 'should release TERM, INT and HUP signals if block given' do
      assert_trap_signal 'TERM', 'INT', 'HUP' do
        assert_release_signal 'TERM', 'INT', 'HUP' do
          @process.trap_signals {}
        end
      end
    end

    it 'should release TERM, INT and HUP signals if exception raised' do
      assert_trap_signal 'TERM', 'INT', 'HUP' do
        assert_release_signal 'TERM', 'INT', 'HUP' do
          @process.trap_signals { raise RuntimeError } rescue nil
        end
      end
    end
  end

  describe '#kernel_fork' do
    it 'should not fork if forks disabled' do
      process = Protein::Process.new
      process.can_fork = false
      count = 0
      Kernel.stub(:fork, Proc.new{count += 1}) { process.send(:kernel_fork) }
      assert_equal 0, count
    end

    it 'should return nil if forks disabled' do
      process = Protein::Process.new
      process.can_fork = false
      Kernel.stub(:fork, nil) do
        assert_nil process.send(:kernel_fork)
      end
    end

    it 'should return fork pid in parent process' do
      Kernel.stub(:fork, 42) do
        assert_equal 42, @process.send(:kernel_fork)
      end
    end

    it 'should return nil in child process' do
      Kernel.stub(:fork, nil) do
        assert_nil @process.send(:kernel_fork)
      end
    end
  end

  describe '#fork' do
    before do
      @process.can_fork = true
    end

    it 'should flush logger' do
      @process.stub :kernel_fork, nil do
        assert_call(@process.logger, :flush) do
          @process.fork
        end
      end
    end

    it 'should return fork pid in parent process' do
      @process.stub :kernel_fork, 42 do
        assert_equal 42, @process.fork
      end
    end

    it 'should return nil in child process' do
      @process.stub :kernel_fork, nil do
        assert_nil @process.fork
      end
    end

    it 'should reset random number generator in parent process' do
      @process.stub :kernel_fork, 42 do
        assert_call(@process, :srand) do
          @process.fork
        end
      end
    end

    it 'should detach from child process' do
      @process.stub :kernel_fork, 42 do
        assert_call(::Process, :detach, 42) do
          @process.fork
        end
      end
    end

    it 'should yield in child process' do
      @process.stub :kernel_fork, nil do
        done = false
        @process.fork { done = true }
        assert done
      end
    end

    it 'should reopen STDERR, STDIN and STDOUT at /dev/null in child process' do
      @process.stub :kernel_fork, nil do
        @process.fork
        assert_equal(
          {:stdin  => ['/dev/null'], :stdout => ['/dev/null'], :stderr => ['/dev/null']},
          @process.io_changes
        )
      end
    end

    it 'should reset work dir in child process' do
      @process.stub :kernel_fork, nil do
        Dir.chdir('/tmp')
        @process.fork
        assert_equal '/', Dir.pwd
      end
    end

    it 'should reconnect in child process' do
      @process.stub :kernel_fork, nil do
        assert_call(@process, :reconnect) do
          @process.fork
        end
      end
    end

    it 'should startup in child process' do
      @process.stub :kernel_fork, nil do
        assert_call(@process, :startup) do
          @process.fork
        end
      end
    end

    it 'should fire after_fork callbacks in child process' do
      @process.stub :kernel_fork, nil do
        recorder = record_callbacks { @process.fork }
        assert_equal [:after_fork], recorder
      end
    end
  end

  describe 'tools' do
    describe '#kill' do
      it 'should send kill signal' do
        count = 0
        @process.tools.stub :exists?, Proc.new{|*_| (count += 1) == 1} do
          assert_call(::Process, :kill, 'KILL', Process.pid) do
            @process.tools.kill(Process.pid)
          end
        end
      end
      it 'should send term signal' do
        count = 0
        @process.tools.stub :exists?, Proc.new{|*_| (count += 1) == 1} do
          assert_call(::Process, :kill, 'TERM', Process.pid) do
            @process.tools.term(Process.pid)
          end
        end
      end
    end
  end
end