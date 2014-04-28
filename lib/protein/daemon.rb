# -*- encoding : utf-8 -*-
module Protein
  class Daemon
    delegate :config, :logger, :process, :to => :Protein

    def run_in_background
      exception_handling do
        process.fork { run }
      end  
    end
    
    def run
      exception_handling do
        unregister_dead_daemon!
        if started?
          logger.info "Another daemon with pid #{pid} is already running"
          return
        end

        register do
          logger.debug "Enter main loop"
          loop do
            unless process.running?
              logger.debug "Exit main loop"
              break
            end
            strategy.loop # payload
            logger.flush
            sleep delay
          end
        end
      end
    end

    def strategy
      @strategy ||= Protein::Strategy.create(config.strategy)
    end

    def delay
      @delay ||= config.main_loop_delay
    end

    def pid
      _pid.get
    end

    def started?
      pid > 0
    end

    def dead?
      started? && !process.tools.exists?(pid)
    end

    def alive?
      started? && process.tools.exists?(pid)
    end

    def to_s
      info.map{ |(key, val)| "#{key}: #{val}"} * ', '
    end

    def info
      {
        :pid => pid,
        :hostname => config.hostname,
        :version => config.version,
        :environment => config.environment,
        :rails => config.rails_root,
        :status => status_string,
        :strategy => config.strategy,
        :concurrency => config.concurrency
      }
    end

    def status_string
      if started?
        "started (#{alive? ? 'alive' : 'dead'})"
      else
        "not started"
      end
    end

    protected

    def register
      _pid.store(process.pid) do
        process.startup
        process.trap_signals do
          process.change_app_name("daemon") do
            logger.info "Daemon started [#{self.to_s}]"
            yield
          end
        end
        logger.debug "Exit"
        logger.close unless logger.stdout?
      end
    end

    def unregister
      _pid.del
    end

    def unregister_dead_daemon!
      if dead?
        logger.warn("Dead daemon detected: process with pid #{pid} not found")
        unregister
      end
      nil
    end

    def exception_handling
      yield if block_given?
    rescue => e
      logger.error ["Unhandled exception #{e.message}", e.backtrace].flatten.join("\n")
      logger.error "Abnormal termination."
      logger.close
      nil
    end

    def _pid
      @_pid ||= Pid.new
    end

    class Pid
      delegate :config, :redis, :logger, :to => :Protein

      #def exists?
      #  redis.exists?(key)
      #end

      def get
        redis.get(key).to_i
      end

      def set(pid)
        logger.debug("Set daemon pid #{pid}")
        redis.set(key, pid)
      end

      def del
        logger.debug("Delete daemon pid")
        redis.del(key)
      end

      def store(pid)
        set(pid)
        yield if block_given?
      ensure
        del
      end

      protected

      def key
        @key ||= "#{config.daemon_key}:#{config.hostname}"
      end
    end
  end

end