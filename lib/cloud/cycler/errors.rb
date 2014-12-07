require 'cloud/cycler/namespace'
class Cloud::Cycler
  Error = Class.new(StandardError)
  TaskFailure = Class.new(Cloud::Cycler::Error)
end
