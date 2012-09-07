# -*- encoding : utf-8 -*-
module Protein
  class Configuration
    class Default
      def root
        self.class.root
      end

      def [](name)
        raise Protein::ConfigurationParameterMissing unless defaults.key?(name)
        defaults[name]
      end

      def defaults
        self.class.all
      end

      def self.root
        File.expand_path('../../../..', __FILE__)
      end

      def self.all
        @all ||= {
          :log_level       => :debug,
          :log_file        => STDOUT,

          :concurrency     => 4,
          :main_loop_delay => 0.025,
          :strategy        => :single,
          :can_fork        => true,
          :use_rails       => true,
          :config_files    => [],

          :sequence_key    => "sequence",
          :daemon_key      => "daemon",
          :workers_key     => "workers",
          :worker_lock_timeout => 1, # in seconds
          :worker_live_time    => 5 * 60, # in seconds
          :worker_jobs_limit   => 1000,

          :process_term_timeout => 10, # in seconds
          :process_kill_timeout => 20, # in seconds

          :queue_key     => "queue",
          :queue_timeout => 5, # in seconds
          :queues        => [:default],

          :maintenance_timeout => 1 * 60, # in seconds

          :redis => {
            :host => 'localhost',
            :port => 6379,
            :namespace => "protein"
          }
        }
      end
    end
  end  
end