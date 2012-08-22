# -*- encoding : utf-8 -*-
module Protein::Strategy
  class Base
    delegate :config, :logger, :callbacks, :to => :Protein

    def initialize
      callbacks.fire(:after_start)
      logger.debug("Strategy #{self.class.name} successfully initialized")
    end

    def loop
      payload
      exception_handling { callbacks.fire(:after_loop) }
    ensure
      maintenance
    end

    def payload
      raise NotImplemented
    end

    protected

    def new_worker(type, &block)
      Protein::Worker.create(type, &block)
    end

    def maintenance
      periodic_maintenance do
        logger.debug "Perform service maintenance"
        Protein::Worker.delete_dead_workers
      end
    end

    def periodic_maintenance
      @last_maintenance_time ||= Time.at(0)
      now = Time.now
      if (@last_maintenance_time + config.maintenance_timeout) < now
        @last_maintenance_time = now
        yield
        true
      else
        false
      end
    end

    def next_job
      Protein::Job.next
    end

    def job_care(job)
      return unless job.present?

      begin
        if block_given?
          yield(job)
        else
          job
        end
      rescue => e
        job.rollback
        raise e
      end
    end

    def exception_handling
      yield
    rescue Protein::TimeoutError => timeout
      logger.debug(timeout.message)
    rescue Protein::TerminationError  
    rescue => e
      error("Unhandled exception", e)
    end

    def log(message)
      logger.info(message)
    end

    def error(message, exception)
      logger.error(message)
      logger.error(exception)
    end
    alias_method :error_log, :error
  end
end
