# -*- encoding : utf-8 -*-
module Protein::Strategy
  class Multi < Single

    def execute_job
      exception_handling do
        logger.debug("Waiting for a job ...")
        # как только в очереди появляется задача - пытаемся выполнить её в новом потоке
        job_care(next_job) do |job|
          logger.debug("Job selected")
          new_worker(:job) do |worker|
            start_thread(worker, job) 
          end
        end
      end
    end

    def start_thread(worker, job)
      # обрабатываем задачи, пока текущий процесс может их обрабатывать (см. stale?)
      catch(:stop_thread) do
        while job
          job_care(job) do
            if worker.stale?
              logger.debug("Worker is stale, terminating")
              throw :stop_thread
            end
            if worker.terminated?
              throw :stop_thread
            end
            worker.execute_job(job)
          end
          logger.debug("Worker has [#{worker.processed}] jobs processed")
          job = next_job
        end
      end  
    end

  end
end
