# -*- encoding : utf-8 -*-
ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'
if ENV.has_key?("SIMPLECOV")
  require 'simplecov'
  SimpleCov.start { add_filter "/test/" }
end

dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift dir + '/../lib'

require 'rubygems'
require 'minitest'
require 'minitest/autorun'
require 'minitest/pride'
require 'protein'

Protein.config do |c|
  c.log_file = File.expand_path('../log/protein.log', File.dirname(__FILE__))
  c.log_level = :error
  c.environment = :test

  c.concurrency = 4
  c.worker_lock_timeout = 5
  c.queue_timeout = 5

  c.worker_live_time = 60 * 60
  c.worker_jobs_limit = 100

  c.can_fork = false

  c.redis = {
    :host => 'localhost',
    :port => 6379,
    :namespace => "protein_test"
  }
  c.finalize
end
def config
  Protein.config
end

module IOProtection
  def self.included(base)
    base.class_eval do
      alias_method :fork_without_io_protection, :fork
      alias_method :fork, :fork_with_io_protection
    end
  end

  def io_changes
    @io_changes
  end

  def write_io_changes
    @io_changes = {:stdin => [], :stdout => [], :stderr => []}
    STDERR.stub :reopen, Proc.new{|f| @io_changes[:stderr] << f} do
      STDOUT.stub :reopen, Proc.new{|f| @io_changes[:stdout] << f} do
        STDIN.stub :reopen, Proc.new{|f| @io_changes[:stdin] << f} do
          yield
        end
      end
    end
  end

  def fork_with_io_protection(&block)
    write_io_changes do
      fork_without_io_protection(&block)
    end
  end
end

module ExitSuppressor
  def self.included(base)
    base.class_eval do
      alias_method :exit_without_suppression, :exit
      alias_method :exit, :exit_with_suppression
    end
  end

  def exit_flag
    @exit_flag
  end

  def stub_exit
    @exit_flag = nil
    ::Process.stub :exit!, Proc.new{ |flag| @exit_flag = flag } do
      yield
    end
    @exit_flag
  end

  def exit_with_suppression
    stub_exit { exit_without_suppression }
  end
end

Protein::Process.send :include, ExitSuppressor
Protein::Process.send :include, IOProtection

CustomConfig = Struct.new('CustomConfig', *Protein::Configuration::Default.all.keys)

class SimpleJob < Protein::Job
  def self.reset_id
    @id = 0
  end
  def self.next_id
    @id ||= 0
    @id += 1
  end

  def initialize(klass, *args)
    super(
      :class => klass.to_s,
      :args => args,
      :id => self.class.next_id,
      :created_at => Time.now.to_f
    )
  end
end

class MiddlewareRecorder
  def initialize(name, recorder)
    @name = name
    @recorder = recorder
  end

  def call(*args)
    @recorder << [@name, 'before']
    yield
    @recorder << [@name, 'after']
  end
end

class SimpleWork
  def self.perform(recorder = nil)
    recorder << ['work_performed'] if recorder.present?
  end
end

class InvalidWork
  def self.perform
    raise RuntimeError
  end
end

def allow_forks
  current, Protein.process.can_fork = Protein.process.can_fork, true
  yield
ensure
  Protein.process.can_fork = current
end

def record_callbacks
  recorder = []
  Protein.callbacks.stub :fire, Proc.new{ |name| recorder << name } do
    yield
  end
  recorder
end

def raise_in_callback(callback, exception)
  proc = Proc.new{ |name| raise exception if name == callback }
  Protein.callbacks.stub :fire, proc do
    yield
  end
end

module Assertions
  def assert_call(object, method, *args, &block)
    done = nil
    object.stub(method, Proc.new{|*call_args| done = call_args if args == call_args}, &block)
    assert_equal args, done
  end

  def assert_call_count(expected, object, method, *args, &block)
    count = 0
    object.stub(method, Proc.new{|*call_args| count += 1 if args == call_args}, &block)
    assert_equal expected, count
  end
end
include Assertions  
