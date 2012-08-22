# -*- encoding : utf-8 -*-
module Protein::Strategy
  class Single < Base

    def payload
      execute_job
    end

    def execute_job
      exception_handling do
        logger.debug("Waiting for a job ...")
        job_care(next_job) do |job|
          logger.debug("Job selected")
          new_worker(:job) do |worker|
            job_care(worker.execute_job(job))
          end
        end
      end
    end

  end
end
