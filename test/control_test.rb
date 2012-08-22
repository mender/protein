require 'test_helper'

describe Protein::Control do
  before do
    @control = Protein::Control.new

  end

  describe '#daemon_started?' do
    it 'should return true if daemon is started and alive' do
      @control.daemon.stub :alive?, true do
        assert @control.daemon_started?
      end
    end

    it 'should return false if daemon is not started or dead' do
      @control.daemon.stub :alive?, false do
        refute @control.daemon_started?
      end
    end
  end

  describe '#daemon_run' do
    it 'should run daemon' do
      @control.stub :daemon_started?, false do
        assert_call @control.daemon, :run do
          @control.daemon_run
        end
      end
    end

    it 'should not run daemon if it is already started' do
      @control.stub :daemon_started?, true do
        assert_call_count 0, @control.daemon, :run do
          @control.daemon_run
        end
      end
    end
  end

  describe '#daemon_start' do
    it 'should start daemon' do
      @control.stub :daemon_started?, false do
        assert_call @control.daemon, :run_in_background do
          @control.daemon_start
        end
      end
    end

    it 'should not run daemon if it is already started' do
      @control.stub :daemon_started?, true do
        assert_call_count 0, @control.daemon, :run_in_background do
          @control.daemon_start
        end
      end
    end
  end

  describe '#daemon_stop' do
    it 'should log if daemon is not started' do
      @control.stub :daemon_started?, false do
        assert_call @control.logger, :info, "Where is no daemon running" do
          @control.daemon_stop
        end
      end
    end

    it 'should return false if daemon is not started' do
      @control.stub :daemon_started?, false do
        refute @control.daemon_stop
      end
    end

    it 'should log if daemon is alive' do
      @control.stub :daemon_started?, true do
        @control.daemon.stub :pid, 42 do
          assert_call @control.logger, :info, "Trying to stop daemon with pid 42" do
            @control.daemon_stop
          end
        end
      end
    end

    it 'should try to stop daemon if daemon is alive' do
      @control.stub :daemon_started?, true do
        @control.daemon.stub :pid, 42 do
          assert_call @control.process.tools, :stop, 42 do
            @control.daemon_stop
          end
        end
      end
    end
  end
end