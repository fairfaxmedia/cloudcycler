require 'cloud/cycler'

# Provides the Domain Specific Language for Cloud::Cycler
class Cloud::Cycler::DSL
  require 'cloud/cycler/dsl/schedule'
  require 'cloud/cycler/dsl/task'

  # Initialize a new Cloud::Cycler::DSL application.
  # * region: Default AWS region
  def initialize(cycler, region)
    @cycler = cycler
    @region = region
  end

  # Set the default S3 bucket to store configuration files, etc.
  # This may be overwritten on a per-task basis.
  def default_bucket(bucket)
    @cycler.bucket = bucket
  end

  # Default prefix (i.e. folder) to prepend to S3 object names
  def default_bucket_prefix(prefix)
    @cycler.bucket_prefix = prefix
  end

  # Default region for S3 buckets, if different from the region being cycled.
  def default_bucket_region(region)
    @cycler.bucket_region = region
  end

  # Sets the application to dryrun mode.
  # Tasks check this value before running #unsafe blocks.
  def dryrun!
    @cycler.dryrun = true
  end

  # Placeholder. Just runs instance_eval currently, but pre/post logic can be
  # added here.
  def run(&block)
    instance_eval(&block)
  end

  # Change the logger. May be any type accepted by Logger::new (i.e. a filename
  # String or an IO).
  def log_to(log_dest)
    @cycler.logger = Logger.new(log_dest)
    @cycler.logger.formatter = proc do |sev, time, prog, msg|
      "#{time} [#{sev}] #{prog} - #{msg}\n"
    end
  end

  # Defines and runs a task. Catches and logs Cloud::Cycler::TaskFailure errors.
  def task(name, &block)
    task = Cloud::Cycler::Task.new(@cycler, name)
    task_dsl = Cloud::Cycler::DSL::Task.new(task)
    task_dsl.instance_eval(&block)
    task.run
  rescue Cloud::Cycler::TaskFailure => e
    if @cycler.logger
      @cycler.logger.error("task:#{name}") { "Task failed: #{e.message}" }
    else $stderr.tty?
      $stderr.puts "task #{name} failed: #{e.message}"
    end
  end
end

# Insert a Cloud::Cycler.run method into Cloud::Cycler
class Cloud::Cycler
  def self.run(region, &block)
    cycler = self.new
    cycler.region = region
    dsl = DSL.new(cycler, region)
    dsl.instance_eval(&block)
    cycler
  end
end
