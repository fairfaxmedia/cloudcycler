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

  attr_accessor :logger        # Logger - may be set with #log_to
  attr_accessor :region        # Default AWS region
  attr_accessor :bucket        # Default S3 bucket
  attr_accessor :bucket_prefix # Prefix (folder) for s3 objects
  attr_accessor :bucket_region # Region for S3 bucket
  attr_accessor :dryrun        # Set to true if application is in dryrun mode

  def log_to(out)
    @logger = Logger.new(log_dest)
    @logger.formatter = proc do |sev, time, prog, msg|
      "#{time} [#{sev}] #{prog} - #{msg}\n"
    end
  end
end
