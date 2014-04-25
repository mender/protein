# encoding: utf-8
require 'protein/worker/collection'
require 'protein/worker/class_methods'
require 'protein/worker_middleware'
require 'protein/middleware/chain'

module Protein
  class Worker
    extend ClassMethods

    delegate :config, :logger, :process, :to => :Protein

    item_accessor :id, :type, :status, :hostname, :started_at, :created_at
    item_accessor :processed, :completed, :failed
    item_accessor :job, :job_started_at
    item_setter   :pid

    def do
      start
      process.trap_signals do
        process.change_app_name("worker #{self.status}") do
          yield(self)
        end
      end
    end

    def execute_job(job)
      return if job.nil?

      self.class.middleware.invoke(self, job) do
        job.execute
      end
    rescue => e
      logger.error e
    end

    def item=(item)
      @item = item
    end

    def item
      @item ||= Protein::Worker::CollectionItemStub.new
    end

    def info
      item.to_h.merge(:status => status_message)
    end

    def status_message
      status = self.status
      status = 'not started' unless started?
      status = 'dead' if dead?
      status
    end

    def real_pid
      process.pid
    end

    def pid
      item.pid
    end

    def dead?
      started? && !process.tools.exists?(pid)
    end

    def alive?
      started? && process.tools.exists?(pid)
    end

    def started?
      pid.present?
    end

    def terminated?
      !process.running?
    end

    def stale?
      (processed >= jobs_limit) || (age >= live_time)
    end

    def jobs_limit
      @@jobs_limit ||= config.worker_jobs_limit
    end

    def live_time
      @@live_time ||= config.worker_live_time
    end

    def age
      started_at.present? ? Time.now - started_at : 0
    end

    def start
      self.started_at = Time.now
      self.pid        = real_pid
      item.save
    end

  end
end
