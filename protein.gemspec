$LOAD_PATH.unshift 'lib'
require 'protein/version'

Gem::Specification.new do |gem|
  gem.name             = "protein"
  gem.version          = Protein::Version
  gem.date             = Time.now.strftime('%Y-%m-%d')
  gem.homepage         = "http://github.com/mender/protein"
  gem.email            = ["main.mender@gmail.com"]
  gem.authors          = [ "Alexei Gorbov" ]
  gem.description      = "Delayed job processing infrastructure"
  gem.summary          = "Delayed job processing infrastructure"

  gem.files            = `git ls-files`.split("\n")
  gem.test_files       = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables      = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths    = ["lib"]

  #gem.extra_rdoc_files = [ "LICENSE", "README.markdown" ]
  #gem.rdoc_options     = ["--charset=UTF-8"]

  gem.add_dependency "redis", ">= 2"
  gem.add_dependency "uuidtools"
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'minitest'
  gem.add_development_dependency 'simplecov'
  gem.add_development_dependency 'mock_redis'
end
