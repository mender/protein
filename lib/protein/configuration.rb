# -*- encoding : utf-8 -*-
require 'protein/configuration/default'

module Protein
  class Configuration
    delegate :root, :project_root, :to => :default
    delegate :callbacks, :to => :Protein

    def self.config_accessor(name)
      name = name.to_s.to_sym
      # setter
      define_method("#{name}=") do |value| 
        raise Protein::ConfigurationError.new("Attempt to modify finalized configuration") if finalized?
        config[name] = value
      end  
      # getter
      define_method(name) do
        finalize 
        config.key?(name) ? config[name] : default[name]
      end  
    end    

    Protein::Configuration::Default.all.each_key do |name|
      config_accessor name
    end

    Protein::Callbacks.names.each do |name|
      delegate name, :to => :callbacks
    end

    def hostname
      @hostname ||= Socket.gethostname
    end

    def version
      Protein::Version
    end

    def rails_root
      @rails_root ||= find_rails
    end

    def rails_root=(root)
      @rails_root = root
    end

    def environment
      @environment ||= begin
        env = ENV["RAILS_ENV"] || ENV['RACK_ENV'] || ENV["ENV"] || ENV["ENVIRONMENT"]
        ActiveSupport::StringInquirer.new(env || "development")
      end  
    end

    def environment=(environment)
      @environment = ActiveSupport::StringInquirer.new(environment.to_s)
    end

    def define(&block)
      yield(self) if block_given?
      self
    end

    def finalize
      return if finalized?
      return if finalization_disabled?
      disable_finalization do
        load_config_files
        load_rails
      end  
      @finalized = true
    end

    def finalized?
      !!@finalized
    end

    protected

    def config
      @config ||= {}
    end

    def default
      @default ||= Protein::Configuration::Default.new
    end

    def finalization_disabled?
      !!@finalization_disabled
    end

    def disable_finalization
      @finalization_disabled = true
      yield
    ensure
      @finalization_disabled = false  
    end

    def load_config_files
      all_config_files.uniq.each do |file|
        if ::File.exists?(file) 
          require file
        elsif ::File.exists?(file + '.rb')
          require file + '.rb'
        end
      end
    end

    def all_config_files
      files = [
        File.join(::Dir.pwd, 'protein'),
        File.join(::Dir.pwd, 'protein.local'),
        File.join(::Dir.pwd, 'config', 'protein'),
        File.join(::Dir.pwd, 'config', 'protein.local')
      ]
      if rails_root.present?
        files += [
          File.join(rails_root, 'config', 'protein'),
          File.join(rails_root, 'config', 'protein.local')
        ]
      end
      files + (self.config_files || [])
    end

    def load_rails
      return unless self.use_rails
      if rails_root
        after_start do
          Dir.chdir(rails_root) do
            Protein.logger.debug "Loading Rails from #{rails_root} ..."
            require File.join(rails_root, 'config', 'application')
            Rails.env    = environment
            Rails.logger = Protein.logger
            require File.join(rails_root, 'config', 'environment')
            # Preload app files
            Rails.application.eager_load!
            Protein.logger.debug "Rails loaded"
          end
        end
        after_fork do
          if rails_loded?
            if ActiveRecord::Base.connected?
              ActiveRecord::Base.connection.reconnect!
              ActiveRecord::Base.verify_active_connections!
            end
            Rails.cache.reset if defined?(RAILS_CACHE)
          end  
        end
      end  
    end    

    def find_rails
      return Rails.root if defined?(Rails)
      return ::Dir.pwd  if rails_path?(::Dir.pwd)
    end

    def rails_path?(path)
      return false if path.blank?
      app_file = File.join(path, 'config', 'application.rb')
      env_file = File.join(path, 'config', 'environment.rb')
      File.exists?(app_file) && File.exists?(env_file)
    end

    def rails_loded?
      defined?(Rails)
    end
  end

end
