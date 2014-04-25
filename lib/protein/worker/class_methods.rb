# encoding: utf-8
module Protein
  class Worker
    module ClassMethods
      delegate :config, :logger, :process, :to => :Protein

      def default_middleware
        Middleware::Chain.new do |m|
          m.add WorkerMiddleware::AppName
          m.add WorkerMiddleware::LogJob
          m.add WorkerMiddleware::LogWork
        end
      end

      def middleware
        @middleware ||= default_middleware
        yield @middleware if block_given?
        @middleware
      end

      def create(type, &block)
        in_fork(type) do |worker|
          begin
            if block_given?
              worker.do(&block)
            else
              worker
            end
          rescue => e
            logger.error "Unhandled exception"
            logger.error e
          ensure
            safe_delete(worker)
            process.exit
          end
        end
      end

      def factory(type, &block)
        collection(type).add(&block)
      end

      def all
        collection_set.all.inject([]) do |result, collection|
          result += collection.workers
          result
        end
      end

      def delete_dead_workers
        collection_set.all.each do |collection|
          collection.dead_workers.each do |worker|
            worker_info = "id: #{worker.id}, pid: #{worker.pid}"
            logger.info "Delete dead worker [#{worker_info}] from collection #{collection.name}"
            collection.delete(worker)
          end
        end
        nil
      end

      def item_getter(*names)
        delegate(*(names + [:to => :item]))
      end

      def item_setter(*names)
        names = names.map { |name| "#{name}=" }
        delegate(*(names + [:to => :item]))
      end

      def item_accessor(*names)
        item_getter(*names)
        item_setter(*names)
      end

      protected

      def in_fork(type, &block)
        factory(type) do |worker|
          begin
            process.fork do
              yield(worker)
            end
          rescue => e
            safe_delete(worker)
            raise e
          end
        end
      end

      def safe_delete(worker)
        collection(worker.type).delete(worker)
      rescue => e
        logger.error(e)
      end

      def collection(type)
        @collections ||= Hash.new do |hash, name|
          hash[name] = collection_set.create(name)
        end
        @collections[type]
      end

      def collection_set
        @collection_set ||= Protein::Worker::Collections.new
      end
    end
  end
end