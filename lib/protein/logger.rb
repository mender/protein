# -*- encoding : utf-8 -*-
require 'logger'

module Protein
  class Logger < ActiveSupport::BufferedLogger
    def initialize(log, level)
      @log_file = log
      super(log, level_number(level))
    end

    def level_number(level)
      case level
      when Integer then level
      else ActiveSupport::BufferedLogger.const_get(level.to_s.upcase)
      end
    end

    def stdout?
      @log_file == STDOUT
    end

    def reopen
      exception_handling do
        unless stdout?
          close
          if @log_file.respond_to?(:write)
            @log = @log_file
          elsif File.exist?(@log_file)
            @log = open_log(@log_file, (File::WRONLY | File::APPEND))
          else
            FileUtils.mkdir_p(File.dirname(@log_file))
            @log = open_log(@log_file, (File::WRONLY | File::APPEND | File::CREAT))
          end
        end
      end
    end

    def add(severity, message = nil, progname = nil, &block)
      exception_handling do
        return if @level > severity
        reopen if closed?
        message = message || (block && block.call) || progname
        message = formatter.call(severity, Time.now, message)
        super(severity, message, progname, &block)
      end
    end

    def close
      exception_handling do
        flush
        @log.close if @log.respond_to?(:close) && !closed?
        @log = nil
      end
    end

    def closed?
      @log.nil? || @log.respond_to?(:closed?) && @log.closed?
    end

    def formatter
      @formatter ||= Formatter.new.tap do |formatter|
        formatter.datetime_format = "%Y-%m-%dT%H:%M:%S.%L"
        formatter.format          = "\e[32m[%s (%d) %s]\e[0m %s"
      end
    end

    def formatter=(formatter)
      @formatter = formatter
    end

    protected

    def exception_handling
      yield if block_given?
    rescue => e
      to_stdout(e)
    end

    def to_stdout(message)
      puts message.inspect
    end

    class Formatter < ::Logger::Formatter
      SEV_LABEL = %w(DEBUG INFO WARN ERROR FATAL ANY)
      attr_accessor :format

      def format_severity(severity)
        SEV_LABEL[severity] || 'ANY'
      end

      def call(severity, time, msg)
        severity = format_severity(severity)
        time     = format_datetime(time)
        (format || Format) % [time, $$, severity[0], msg2str(msg)]
      end
    end
  end

end
