# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'prkit/version'

Gem::Specification.new do |gem|
  gem.name          = 'prkit'
  gem.version       = Prkit::VERSION
  gem.authors       = ['chrismo']
  gem.email         = ['chrismo@clabs.org']
  gem.description   = %q{Simple gem to idempotently handle PR creation for a GitHub repo.}
  gem.summary       = ''
  gem.homepage      = 'https://github.com/livingsocial/prkit'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'git'
  gem.add_dependency 'octokit'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
end
