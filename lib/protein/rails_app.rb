# encoding: utf-8
module Protein
  class RailsApp
    RAILS_ENV = ENV["RAILS_ENV"]

    def self.defined?
      defined?(Rails)
    end

    def defined?
      self.class.defined?
    end

    def root
      @root ||= find
    end

    def root=(path)
      @root = path
    end

    def find
      return Rails.root if defined?(Rails)
      return ::Dir.pwd  if rails_path?(::Dir.pwd)
    end

    def rails_path?(path)
      return false if path.blank?
      app_file = File.join(path, 'config', 'application.rb')
      env_file = File.join(path, 'config', 'environment.rb')
      File.exists?(app_file) && File.exists?(env_file)
    end

    def load(env)
      define_callbacks(env) if root
    end

    protected

    def define_callbacks(env)
      after_start_callback(env)
      after_fork_callback(env)
    end

    def after_start_callback(env)
      Protein.callbacks.after_start do
        Protein.logger.debug "Loading Rails from #{root} ..."
        RailsApp::Loader.load(root) do |rails|
          rails.env    = env
          rails.logger = Protein.logger
        end
        Protein.logger.debug "Rails loaded"
      end
    end

    def after_fork_callback(env)
      return unless self.defined?
      Protein.callbacks.after_fork do
        if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
          ActiveRecord::Base.connection.reconnect!
          ActiveRecord::Base.verify_active_connections!
        end
        if defined?(RAILS_CACHE) && Rails.cache.respond_to?(:reset)
          Rails.cache.reset 
        end  
      end
    end

    class Loader
      def self.load(root, &block)
        Dir.chdir(root) do
          load_app(&block) 
          load_env
          eager_load
        end
      end

      protected

      def self.load_app
        require File.join(::Dir.pwd, 'config', 'application')
        yield(Rails) if block_given?
      end

      def self.load_env
        require File.join(::Dir.pwd, 'config', 'environment')
      end

      def self.eager_load
        Rails.application.eager_load!
      end
    end
  end
end