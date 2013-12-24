# -*- encoding : utf-8 -*-
require 'logger'

module Protein
  class Logger
    module Severity
      DEBUG   = 0
      INFO    = 1
      WARN    = 2
      ERROR   = 3
      FATAL   = 4
      UNKNOWN = 5
    end
    include Severity

    MAX_BUFFER_SIZE = 1000

    attr_accessor :level
    attr_reader :auto_flushing

    ##
    # :singleton-method:
    # Set to false to disable the silencer
    cattr_accessor :silencer
    self.silencer = true

    def silence(temporary_level = ERROR)
      if silencer
        begin
          old_logger_level, self.level = level, temporary_level
          yield self
        ensure
          self.level = old_logger_level
        end
      else
        yield self
      end
    end

    def initialize(log, level = DEBUG)
      @log_file      = log
      @level         = level_number(level)
      @buffer        = Hash.new { |h,k| h[k] = [] }
      @auto_flushing = 1
      @guard = Mutex.new

      if log.respond_to?(:write)
        @log = log
      elsif File.exist?(log)
        @log = open_log(log, (File::WRONLY | File::APPEND))
      else
        FileUtils.mkdir_p(File.dirname(log))
        @log = open_log(log, (File::WRONLY | File::APPEND | File::CREAT))
      end
    end

    def level_number(level)
      case level
      when Integer then level
      else self.class.const_get(level.to_s.upcase)
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
        message = "#{message}\n" unless message[-1] == ?\n
        buffer << message
        auto_flush
        message
      end
    end

    # Dynamically add methods such as:
    # def info
    # def warn
    # def debug
    for severity in Severity.constants
      class_eval <<-EOT, __FILE__, __LINE__ + 1
        def #{severity.downcase}(message = nil, progname = nil, &block) # def debug(message = nil, progname = nil, &block)
          add(#{severity}, message, progname, &block)                   #   add(DEBUG, message, progname, &block)
        end                                                             # end

        def #{severity.downcase}?                                       # def debug?
          #{severity} >= @level                                         #   DEBUG >= @level
        end                                                             # end
      EOT
    end

    # Set the auto-flush period. Set to true to flush after every log message,
    # to an integer to flush every N messages, or to false, nil, or zero to
    # never auto-flush. If you turn auto-flushing off, be sure to regularly
    # flush the log yourself -- it will eat up memory until you do.
    def auto_flushing=(period)
      @auto_flushing =
        case period
        when true;                1
        when false, nil, 0;       MAX_BUFFER_SIZE
        when Integer;             period
        else raise ArgumentError, "Unrecognized auto_flushing period: #{period.inspect}"
        end
    end

    def flush
      @guard.synchronize do
        buffer.each do |content|
          @log.write(content)
        end

        # Important to do this even if buffer was empty or else @buffer will
        # accumulate empty arrays for each request where nothing was logged.
        clear_buffer
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

    def auto_flush
      flush if buffer.size >= @auto_flushing
    end

    def buffer
      @buffer[Thread.current]
    end

    def clear_buffer
      @buffer.delete(Thread.current)
    end

    def open_log(log, mode)
      open(log, mode).tap do |log|
        log.set_encoding(Encoding::BINARY) if log.respond_to?(:set_encoding)
        log.sync = true
      end
    end

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
