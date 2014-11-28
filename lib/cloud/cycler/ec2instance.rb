require 'cloud/cycler/namespace'

# Wrapper around AWS::EC2. 
class Cloud::Cycler::EC2Instance
  def initialize(task, instance_id)
    @task        = task
    @instance_id = instance_id
  end

  def stop
    unless ec2_instance.exists?
      raise Cloud::Cycler::TaskFailure.new("EC2 instance '#{@instance_id}' does not exist")
    end

    if ec2_instance.status == :running
      @task.unsafe("Stopping instance #{@instance_id}") do
        ec2_instance.stop
      end
    elsif ec2_instance.status == :stopped
      @task.debug { "Instance #{@instance_id} already stopped" }
    else
      @task.debug { "Cannot stop #{@instance_id} - instance is not running (status: #{instance.status})" }
    end
  rescue AWS::EC2::Errors::InvalidInstanceID => e
    err = Cloud::Cycler::TaskFailure.new(e.message)
    err.set_backtrace(e.backtrace)
    raise err
  end

  def start
    unless ec2_instance.exists?
      raise Cloud::Cycler::TaskFailure.new("EC2 instance '#{@instance_id}' does not exist")
    end

    if ec2_instance.status == :stopped
      @task.unsafe("Stopping instance #{@instance_id}") do
        ec2_instance.start
      end
    elsif ec2_instance.status == :running
      @task.debug { "Instance #{@instance_id} already running" }
    else
      @task.debug { "Cannot start #{@instance_id} - instance is not stopped (status: #{ec2_instance.status})" }
    end
  end

  def started?
    ec2_instance.status == :running
  end

  private

  def ec2_instances
    return @ec2_instances if defined? @ec2_instances
    ec2 = AWS::EC2.new(:region => @task.region)
    @ec2_instances = ec2.instances
  end

  def ec2_instance
    @ec2_instance ||= ec2_instances[@instance_id]
  end
end
