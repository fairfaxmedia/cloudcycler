require 'rake/clean'

VERSION = '2.0.0'

file "cloudcycler-#{VERSION}.gem" do
  sh "gem build cloudcycler.gemspec"
end
CLEAN << "cloudcycler-#{VERSION}.gem"

task :build do
  sh "gem build cloudcycler.gemspec"
end

task :rdoc do
  sh 'rdoc lib bin'
end

task :default => "cloudcycler-#{VERSION}.gem"
task :install => "cloudcycler-#{VERSION}.gem" do
  sh "gem install ./cloudcycler-#{VERSION}.gem"
end
