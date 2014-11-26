# CloudCycler is a tool for turning off AWS resources at different times of day
# to reduce costs.
#
# Most features are currently implemented under Cloud::Cycler::DSL

require 'cloud'
require 'aws-sdk'
require 'logger'

class Cloud::Cycler
  require 'cloud/cycler/errors'

  # Shortcut to run a Cloud::Cycler::DSL application
  def self.run(region, &block)
    dsl = DSL.new(region)
    dsl.run(&block)
  end
end
