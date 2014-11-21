Gem::Specification.new do |s|
  s.name        = "cloudcycler"
  s.version     = '2.0.0'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["David Baggerman"]
  s.email       = ["david.baggerman@fairfaxmedia.com.au"]
  s.homepage    = "https://bitbucket.org/fairfax/oh-aws-cloudcycler"
  s.summary     = %q{A utility to stop/start instances in EC2}
  s.description = %q{Run this script via cron to start or stop a list of EC2 instances, or instances defined by tags.}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

#  s.post_install_message = "\e[1;32m\n" + ('-' * 79) + "\n\n" + File.read('PostInstall.txt') + "\n" + ('-' * 79) + "\n\e[0m"
end
