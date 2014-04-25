# -*- encoding : utf-8 -*-
require 'protein/configuration/default'
require 'protein/configuration/accessor'

module Protein
  class Configuration
    delegate :root, :project_root, :to => :default
    delegate :callbacks, :to => :Protein

    extend Accessor

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

    def rails_app
      @rails_app ||= Protein::RailsApp.new
    end

    def rails_root
      rails_app.root
    end

    def rails_root=(path)
      rails_app.root = path
    end

    def environment
      @environment ||= begin
        env = RailsApp::RAILS_ENV || ENV['RACK_ENV'] || ENV["ENV"] || ENV["ENVIRONMENT"]
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
        load_rails(environment)
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

    def load_rails(env)
      self.use_rails && rails_app.load(env)
    end    

    def find_rails
      rails_app.find
    end

    def rails_path?(path)
      rails_app.rails_path?(path)
    end

    def rails_loded?
      rails_app.defined?
    end
  end

end
