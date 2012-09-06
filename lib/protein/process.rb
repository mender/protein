# -*- encoding : utf-8 -*-
module Protein
  class Process
    delegate :config, :logger, :redis, :callbacks, :to => :Protein
    attr_accessor :running
    attr_accessor :can_fork

    def initialize
      self.can_fork = config.can_fork
      self.running  = false
    end

    def running?
      !!self.running
    end

    def startup
      #trap_signals
      enable_gc_optimizations
      self.running = true
      $stdout.sync = true
      logger.debug "Process started up"
    end

    def stop
      logger.info "Process termination ..."
      self.running = false
    end

    def trap_signals
      signals.trap("TERM") { stop }
      signals.trap("INT")  { stop }
      signals.trap("HUP")  { logger.debug 'SIGHUP received' }
      if block_given?
        begin
          yield
        ensure
          release_signals
        end
      end
      nil
    end

    def release_signals
      signals.release("TERM")
      signals.release("INT")
      signals.release("HUP")
      nil
    end

    def pid
      ::Process.pid
    end

    def app_name
      $0
    end

    def app_name=(name)
      $0 = name
    end

    def change_app_name(name)
      name = "Protein: #{name}"
      if block_given?
        begin
          self.app_name, previous = name, self.app_name
          yield
        ensure
          self.app_name = previous
        end
      else
        self.app_name = name
      end
    end

    def can_fork?
      !!self.can_fork
    end

    def fork
      before_spawn
      if fork = kernel_fork
        # in parent
        after_spawn(fork)
        fork
      else
        # in child
        after_fork if can_fork?
        if block_given?
          yield
        else
          nil
        end
      end
    end

    def reconnect
      logger.reopen
      redis.reconnect
    end

    def exit
      begin
        callbacks.fire(:before_exit)
      rescue => e
        logger.error(e)
      end
      begin
        logger.debug "Exit"
        logger.close
      rescue
      end
    ensure
      ::Process.exit!(true)
    end

    def tools
      @tools ||= Protein::ProcessTools.new.tap do |tools|
        tools.logger       = self.logger
        tools.term_timeout = config.process_term_timeout 
        tools.kill_timeout = config.process_kill_timeout 
      end
    end

    def signals
      @signals ||= Protein::ProcessSignals.new.tap do |signals|
        signals.logger = self.logger
      end
    end

    # def daemonize
    #   if ::Process.respond_to?(:daemon)
    #     ::Process.daemon
    #   else
    #     null_io
    #     reset_dir
    #   end
    # end

    protected

    # Platform dependent
    def kernel_fork
      return unless can_fork?

      if Kernel.respond_to?(:fork)
        Kernel.fork
      else
        self.can_fork = false
        nil
      end
    end

    def enable_gc_optimizations
      if GC.respond_to?(:copy_on_write_friendly=)
        GC.copy_on_write_friendly = true
      end
    end

    def null_io
      null_file = "/dev/null"
      [STDIN, STDOUT, STDERR].each do |io|
        io.reopen(null_file) rescue nil
      end
    end

    def reset_dir
      ::Dir.chdir("/")
    end

    def after_fork
      null_io
      reset_dir
      reconnect
      startup
      callbacks.fire(:after_fork)
      logger.debug "Succesfully forked"
    end

    def before_spawn
      logger.debug "Creating fork ..."
      logger.flush
    end

    def after_spawn(fork)
      logger.info "Process with pid #{fork} has been created"
      srand # Split rand streams between spawning and forked process
      ::Process.detach(fork)
    end
  end

  class ProcessSignals
    attr_writer :logger

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def trap(signal, &block)
      logger.debug("Trap signal #{signal}")
      handlers[signal].push(::Signal.trap(signal, &block))
      nil
    end

    def release(signal)
      logger.debug("Restore previous signal handler for #{signal}")
      handler = handlers[signal].pop
      if handler.present?
        ::Signal.trap(signal, handler)
      else
        ::Signal.trap(signal, "DEFAULT")
      end
      nil
    end

    def handlers
      @handlers ||= Hash.new do |hash, name| 
        hash[name] = []
      end
    end
  end

  class ProcessTools
    require 'timeout'
    attr_writer :logger
    attr_writer :term_timeout
    attr_writer :kill_timeout
    
    def exists?(pid)
      pid = pid.to_i
      (pid > 0) && (::Process.kill(0, pid) > 0) rescue false
    end

    def stop(pid)
      return false unless l_exists?(pid)
      term(pid)
    end

    def stop!(pid)
      return false unless l_exists?(pid)
      term(pid) or kill(pid)
    end

    def stop_all(pids)
      return false if pids.blank?

      threaded_map(pids){ |pid| stop(pid) }.all?
    end

    def stop_all!(pids)
      return false if pids.blank?

      threaded_map(pids){ |pid| stop!(pid) }.all?
    end

    def threaded_map(values)
      threads = values.map do |value|
        Thread.new { yield(value) }
      end

      threads.map {|t| t.value}
    end

    def term(pid)
      return false unless l_exists?(pid)

      handle_errors do
        timeout(term_timeout) do
          logger.info "Send TERM signal to process with pid #{pid}..."
          ::Process.kill('TERM', pid)
          sleep(1) while exists?(pid)
          logger.info "Process with pid #{pid} successfully terminated"
          return true
        end
      end

      logger.info "Unable to terminate process with pid #{pid}"
      false
    end

    def kill(pid)
      return false unless l_exists?(pid)

      handle_errors do
        timeout(kill_timeout) do
          logger.info "Send KILL signal to process with pid #{pid}..."
          ::Process.kill('KILL', pid)
          sleep(1) while exists?(pid)
          logger.info "Process with pid #{pid} successfully killed"
          return true
        end
      end

      logger.info "Unable to kill process with pid #{pid}"
      false
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def term_timeout
      @term_timeout ||= 10.seconds
    end

    def kill_timeout
      @kill_timeout ||= 20.seconds
    end

    protected

    def l_exists?(pid)
      unless exists?(pid)
        logger.info("Process with pid #{pid} doesn't exists")
        return false
      end
      true
    end

    def handle_errors
      yield if block_given?
    rescue => e
      logger.error(e)
      nil
    end

    def timeout(seconds)
      Timeout::timeout(seconds) do
        yield if block_given?
      end
    rescue Timeout::Error
      nil
    end
  end

end
