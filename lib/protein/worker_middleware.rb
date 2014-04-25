# encoding: utf-8
module Protein
  module WorkerMiddleware
    class AppName
      def call(worker, job, &block)
        name = "job #{job.id}##{job.klass_name}"
        worker.process.change_app_name(name, &block)
      end
    end

    class LogJob
      def call(worker, job)
        worker.logger.info "Executing job #{job.to_s}"
        result = yield
        worker.logger.info "Finished job #{job.id}##{job.klass_name}"
        result
      rescue => e
        worker.logger.error "Failed job #{job.inspect}"
        raise e
      end
    end

    class LogWork
      def call(worker, job)
        worker.item.working_on(job)
        result = yield
        worker.item.success
        result
      rescue => e
        worker.item.fail
        raise e
      end
    end
  end
end