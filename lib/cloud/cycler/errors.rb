require 'cloud/cycler/namespace'

class Cloud::Cycler
  Error        = Class.new(StandardError)
  CycleFailure = Class.new(Cloud::Cycler::Error)
  TaskFailure  = Class.new(Cloud::Cycler::Error)
end
