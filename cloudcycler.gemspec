# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'cloud/cycler/version'

Gem::Specification.new do |spec|
  spec.name        = "cloudcycler"
  spec.version     = Cloud::Cycler::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ["David Baggerman"]
  spec.email       = ["david.baggerman@fairfaxmedia.com.au"]
  spec.homepage    = "https://github.com/fairfaxmedia/cloudcycler"
  spec.summary     = %q{A utility to stop/start instances in EC2}
  spec.description = %q{Run this script via cron to start or stop a list of EC2 instances, or instances defined by tags.}
  spec.licenses    = ['Apache License, Version 2.0']

  spec.files         = `git ls-files`.split("\n")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.add_runtime_dependency 'aws-sdk', '~> 1.58', '< 2.0'
  spec.add_runtime_dependency 'json', '~> 1.7', '< 2.0'
  spec.add_runtime_dependency 'trollop'
end
