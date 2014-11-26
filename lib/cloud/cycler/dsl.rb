require 'cloud/cycler'

# Provides the Domain Specific Language for Cloud::Cycler
class Cloud::Cycler::DSL
  require 'cloud/cycler/dsl/schedule'
  require 'cloud/cycler/dsl/task'

  attr_accessor :logger # Logger - may be set with #log_to
  attr_reader   :region # Default AWS region
  attr_reader   :bucket # Default S3 bucket
  attr_reader   :bucket_prefix # Prefix (folder) for s3 objects
  attr_reader   :bucket_region # Region for S3 bucket
  attr_reader   :dryrun # Set to true if application is in dryrun mode

  # Initialize a new Cloud::Cycler::DSL application.
  # * region: Default AWS region
  def initialize(region)
    @region = region
  end

  # Set the default S3 bucket to store configuration files, etc.
  # This may be overwritten on a per-task basis.
  def default_bucket(bucket)
    @bucket = bucket
  end

  def default_bucket_prefix(prefix)
    @bucket_prefix = prefix
  end

  def default_bucket_region(region)
    @bucket_region = region
  end

  # Sets the application to dryrun mode.
  # Tasks check this value before running #unsafe blocks.
  def dryrun!
    @dryrun = true
  end

  # Placeholder. Just runs instance_eval currently, but pre/post logic can be
  # added here.
  def run(&block)
    instance_eval(&block)
  end

  # Change the logger. May be any type accepted by Logger::new (i.e. a filename String or an IO).
  def log_to(log_dest)
    @logger = Logger.new(log_dest)
    @logger.formatter = proc do |sev, time, prog, msg|
      "#{time} [#{sev}] #{prog} - #{msg}\n"
    end
  end

  # Defines and runs a task. Catches and logs Cloud::Cycler::TaskFailure errors.
  def task(name, &block)
    task = Task.new(self, name)
    task.run(&block)
  rescue Cloud::Cycler::TaskFailure => e
    @logger.error("task:#{name}") { "Task failed: #{e.message}" } 
  end
end 

class Cloud::Cycler
  def self.run(region, &block)
    dsl = DSL.new(region)
    dsl.run(&block)
  end
end
