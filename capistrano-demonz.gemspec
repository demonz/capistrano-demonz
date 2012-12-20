# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'demonz/version'

Gem::Specification.new do |gem|
  gem.name          = "capistrano-demonz"
  gem.version       = Capistrano::Demonz::VERSION
  gem.authors       = ["Chinthaka Godawita"]
  gem.email         = ["chinthaka.godawita@demonzmedia.com"]
  gem.description   = "Demonz Media recipes for Capistrano"
  gem.summary       = "Useful task libraries for Demonz Media recipes for Capistrano"
  gem.homepage      = "https://github.com/demonz/capistrano-demonz"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency  "railsless-deploy"
  gem.add_dependency  "capistrano"
end
