require 'cctest/cycler'
require 'cctest/task'
require 'cctest/instance'
require 'cctest/s3'
require 'cctest/cloudformation'

MissingStub = Class.new(StandardError)

module AWS
  module EC2
    module Errors
      InvalidInstanceID = Class.new(StandardError)
    end
  end
end

