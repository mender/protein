# -*- encoding : utf-8 -*-
module Protein
  class Control
    delegate :config, :logger, :daemon, :process, :to => :Protein

    def stop
      daemon_stop
      workers_stop
    end

    def stop!
      daemon_stop!
      workers_stop!
    end

    def start
      daemon_start
    end

    def run
      daemon_run
    end

    def restart
      stop
      start
    end

    def restart!
      stop!
      start
    end

    def info
      {
        :daemon  => daemon_info,
        :workers => workers_info
      }
    end

    def status_message
      info = self.info
      result = "Daemon:\n"
      result << info[:daemon].map { |(key, val)| "  #{key}: #{val}" } * "\n"
      result << "\n"
      result << "Queues:\n"
      result << queues_length
      result << "\n"
      result << info[:workers].map { |w| "Worker:\n" + w.map { |(key, val)| "  #{key}: #{val}" } * "\n" } * "\n"
    end

    def daemon_start
      !l_daemon_started? and daemon.run_in_background
    end

    def daemon_started?
      daemon.alive?
    end

    def daemon_stop(force = false)
      if daemon_started?
        logger.info "Trying to stop daemon with pid #{daemon.pid}"
        if force
          process.tools.stop!(daemon.pid)
        else
          process.tools.stop(daemon.pid)
        end
      else
        logger.info "Where is no daemon running"
        false
      end
    end

    def daemon_stop!
      daemon_stop(true)
    end

    def daemon_run
      !l_daemon_started? and daemon.run
    end

    def daemon_restart
      daemon_stop if daemon_started?
      daemon_start
    end

    def daemon_restart!
      daemon_stop! if daemon_started?
      daemon_start
    end

    def worker_pids
      workers.map(&:pid).compact.uniq
    end

    def worker_started?(worker)
      worker.alive?
    end

    def worker_stop(worker, force = false)
      logger.info "Trying to stop worker with pid #{worker.pid}"
      if force
        process.tools.stop!(worker.pid)
      else
        process.tools.stop(worker.pid)
      end
    end

    def worker_stop!(worker)
      worker_stop(worker, true)
    end

    def workers_stop(force = false)
      if (pids = worker_pids).present?
        logger.info "Trying to stop workers with pids #{pids}"
        if force 
          process.tools.stop_all!(pids)
        else
          process.tools.stop_all(pids)
        end
      else
        logger.info "Active workers not found."
        false
      end
    end

    def workers_stop!
      workers_stop(true)
    end

    def daemon_info
      daemon.info
    end

    def workers_info
      workers.map { |worker| worker.info }
    end

    def queues_length
      result = []

      Protein::Queue.names.each do |queue_name|
        result << "  #{queue_name}: #{Protein::Queue.find(queue_name).length}"
      end

      result * "\n"
    end

    protected

    def workers
      Protein::Worker.all
    end

    def l_daemon_started?
      if daemon_started?
        logger.info "Another daemon with pid #{daemon.pid} is already running"
        true
      else
        false
      end
    end
  end

end
