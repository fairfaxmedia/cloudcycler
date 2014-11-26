# CloudCycler is a tool for turning off AWS resources at different times of day
# to reduce costs.
#
# Most features are currently implemented under Cloud::Cycler::DSL

require 'cloud'
require 'aws-sdk'
require 'logger'

class Cloud::Cycler
  require 'cloud/cycler/version'
  require 'cloud/cycler/errors'
end
