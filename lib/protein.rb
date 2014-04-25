# -*- encoding : utf-8 -*-
require 'active_support/all'

require 'protein/version'
require 'protein/error'
require 'protein/callbacks'
require 'protein/rails_app'
require 'protein/configuration'
require 'protein/logger'
require 'protein/redis'
require 'protein/queue'
require 'protein/job'
require 'protein/strategy'
require 'protein/process'
require 'protein/daemon'
require 'protein/worker'
require 'protein/control'

module Protein

  class << self
    def do(klass, *args)
      Protein::Job.create(klass, *args)
    end

    def callbacks
      @callbacks ||= Protein::Callbacks.new
    end

    def config(&block)
      @config ||= Protein::Configuration.new
      @config.define(&block) if block_given?
      @config
    end

    def control
      @control ||= Protein::Control.new
    end

    def daemon
      @daemon ||= Protein::Daemon.new
    end

    def logger
      config.finalize unless config.finalized?
      #raise Protein::Error.new("Attempt to get logger while configuration is not finalized") unless config.finalized?
      @logger ||= Protein::Logger.new(config.log_file, config.log_level).tap do |logger|
        logger.auto_flushing = !config.environment.production?
      end
    end

    def process
      @process ||= Protein::Process.new
    end

    def redis
      #@redis ||= Protein::Redis.new
      @redis ||= Protein::Redis.new
    end
  end

end