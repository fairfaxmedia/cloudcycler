require 'cloud/cycler/namespace'

# Wrapper around AWS::EC2. 
class Cloud::Cycler::EC2Instance
  def initialize(task, instance_id)
    @task        = task
    @instance_id = instance_id
  end

  # Shut down the ec2 instance
  def stop(action = :default)
    unless ec2_instance.exists?
      raise Cloud::Cycler::TaskFailure.new("EC2 instance '#{@instance_id}' does not exist")
    end

    if status == :running
      @task.unsafe("Stopping instance #{@instance_id}") do
        ec2_instance.stop
      end
    elsif status == :stopped
      @task.debug { "Instance #{@instance_id} already stopped" }
    else
      @task.debug { "Cannot stop #{@instance_id} - instance is not running (status: #{status})" }
    end
  rescue AWS::EC2::Errors::InvalidInstanceID => e
    err = Cloud::Cycler::TaskFailure.new(e.message)
    err.set_backtrace(e.backtrace)
    raise err
  end

  # Start the ec2 instance
  def start(action = :default)
    unless ec2_instance.exists?
      raise Cloud::Cycler::TaskFailure.new("EC2 instance '#{@instance_id}' does not exist")
    end

    if status == :stopped
      @task.unsafe("Starting instance #{@instance_id}") do
        ec2_instance.start
      end
    elsif status == :running
      @task.debug { "Instance #{@instance_id} already running" }
    else
      @task.debug { "Cannot start #{@instance_id} - instance is not stopped (status: #{status})" }
    end
  end

  def started?
    status == :running
  end

  private

  def status
    @ec2_status ||= ec2_instance.status
  end

  # Memoization for AWS::EC2::InstanceCollection
  def ec2_instances
    return @ec2_instances if defined? @ec2_instances
    ec2 = AWS::EC2.new(@task.aws_config)
    @ec2_instances = ec2.instances
  end

  # Memoization for AWS::EC2::Instance
  def ec2_instance
    @ec2_instance ||= ec2_instances[@instance_id]
  end
end
