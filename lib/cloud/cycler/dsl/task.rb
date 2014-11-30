# A Cloud Cycler task takes a defined list of resources and a schedule and
# turns them off during 'off' hours and restarts them during 'on' hours.
class Cloud::Cycler::DSL::Task
  require 'cloud/cycler/schedule'

  # Create a new task with a reference to a Cloud::Cycler::DSL application and
  # a task name.
  def initialize(task)
    @task = task
  end

  # Convenience method. Defers to the logger of the parent Cloud::Cycler::DSL.
  def logger
    @cycler.logger
  end

  # Overwrite the default region provided by the parent application
  def region(region)
    @task.region = region
  end
  alias :use_region :region

  # Overwrite the default S3 bucket provided by the parent application
  def bucket(bucket)
    @task.bucket = bucket
  end
  alias :use_bucket :bucket

  def bucket_prefix(prefix)
    @task.bucket_prefix = prefix
  end
  alias :use_bucket_prefix :bucket_prefix

  def bucket_region(region)
    @task.bucket_region = region
  end
  alias :use_bucket_region :bucket_region

  # Provide a list of EC2 instances by instance id to be cycled.
  def ec2_include(*ids)
    ids.each do |id|
      @task.include(:ec2, id)
    end
  end

  # Blacklist ec2 instances to be excluded from pattern matching, etc.
  def ec2_exclude(*ids)
    ids.each do |id|
      @task.exclude(:ec2, id)
    end
  end

  # A list of cloudformation stacks to be cycled.
  def cloudformation_include(*names)
    names.each do |name|
      @task.include(:cfn, name)
    end
  end

  # Blacklist cloudformation stacks to be excluded from pattern matching, etc.
  def cloudformation_exclude(*names)
    names.each do |name|
      @task.exclude(:cfn, name)
    end
  end

  def cfn_rds_snapshot_parameter(parameter)
    @task.rds_snapshot_parameter = parameter
  end

  # Defines the schedule for the task.
  def schedule(spec)
    @task.schedule = Cloud::Cycler::Schedule.parse(spec)
  end

  def ec2_action(action)
    @task.actions[:ec2] = action
  end

  def cf_action(action)
    @task.actions[:cfn] = action
  end
end
