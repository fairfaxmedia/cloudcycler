
file 'cloudcycler-2.0.0.gem' do
  sh "gem build cloudcycler.gem"
end

task :build => 'cloudcycler-2.0.0.gem'

task :install => 'cloudcycler-2.0.0.gem' do
  sh "gem install cloudcycler-*.gem"
end
