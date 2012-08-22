require 'test_helper'

describe Protein::Middleware::Chain do
  class NonYieldingMiddleware
    def call(*args)
    end
  end

  it 'supports custom middleware' do
    chain = Protein::Middleware::Chain.new
    chain.add MiddlewareRecorder, 1, []

    assert_equal MiddlewareRecorder, chain.entries.last.klass
  end

  it 'executes middleware in the proper order' do
    recorder = []
    job = SimpleJob.new(SimpleWork, recorder)

    Protein::Worker.middleware do |chain|
      # should only add once, second should be ignored
      2.times { |i| chain.add MiddlewareRecorder, i.to_s, recorder }
    end

    worker = Protein::Worker.new
    worker.execute_job(job)
    assert_equal %w(0 before work_performed 0 after), recorder.flatten
  end

  it 'allows middleware to abruptly stop processing rest of chain' do
    recorder = []
    chain = Protein::Middleware::Chain.new
    chain.add NonYieldingMiddleware
    chain.add MiddlewareRecorder, 1, recorder

    final_action = nil
    chain.invoke { final_action = true }
    assert_equal nil, final_action
    assert_equal [], recorder
  end

  it 'removes specified middleware' do
    chain = Protein::Middleware::Chain.new
    chain.add NonYieldingMiddleware
    chain.add MiddlewareRecorder, 1, []

    chain.remove(NonYieldingMiddleware)

    assert_equal 1, chain.entries.length
    assert_equal MiddlewareRecorder, chain.entries.last.klass
  end

  it 'clears all' do
    chain = Protein::Middleware::Chain.new
    chain.add NonYieldingMiddleware
    chain.add MiddlewareRecorder, 1, []

    chain.clear
    assert_empty chain.entries
  end
end
