$LOAD_PATH.unshift 'lib'
require 'protein/tasks'
require 'rake/testtask'

Rake::TestTask.new do |test|
  #test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/*_test.rb']
end

task :default => :test