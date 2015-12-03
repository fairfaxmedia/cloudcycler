require 'json'
require 'cloud/cycler/namespace'

# Wrapper around AWS::AutoScaling.
class Cloud::Cycler::ASGroup
  attr_accessor :grace_period

  def initialize(task, name)
    @task         = task
    @name         = name
    @grace_period = 30
  end

  # Restart any stopped instances, and resume autoscaling processes.
  def start
    if !autoscaling_group.exists?
      @task.warn { "Autoscaling group #{@name} doesn't exist" }
      return
    end

    if autoscaling_group.suspended_processes.empty?
      @task.debug { "Scaling group #{@name} already running" }
    else
      start_instances

      @task.unsafe("Resuming #{@name} processes") do
        autoscaling_group.resume_all_processes
      end
    end
  end

  # Suspend the autoscaling processes and either terminate or stop the EC2
  # instances under the autoscaling group.
  def stop(action)
    if !autoscaling_group.exists?
      @task.warn { "Autoscaling group #{@name} doesn't exist" }
      return
    end

    if autoscaling_group.suspended_processes.empty?
      case action
      when :default, :terminate
        terminate_instances
      when :stop
        stop_instances
      else
        raise Cloud::Cycler::TaskFailure.new("Unrecognised autoscaling action #{action}")
      end
    else
      @task.debug { "Scaling group #{@name} already suspended" }
    end
  end

  # Terminate all the EC2 instances under the autoscaling group.
  def terminate_instances
    @task.unsafe("Stopping #{@name} Launch process") do
      autoscaling_group.suspend_all_processes
    end
    autoscaling_instances.each do |instance|
      @task.unsafe("Terminating instance #{instance.instance_id}") do
        load_balancers.each do |elb|
          elb.instances.deregister(instance.instance_id)
        end
        instance.ec2_instance.terminate
      end
    end
  end

  # Stop all the instances under the autoscaling group.
  # Normally, autoscaling instances should be safe to add/remove dynamically.
  # However, systems like CQ require manual intervention to add/remove
  # instances.
  def stop_instances
    @task.unsafe("Stopping #{@name} processes") do
      autoscaling_group.suspend_all_processes
    end
    autoscaling_instances.each do |instance|
      @task.unsafe("Stopping instance #{instance.instance_id}") do
        load_balancers.each do |elb|
          elb.instances.deregister(instance.instance_id)
        end
        instance.ec2_instance.stop
      end
    end
  end

  # Restart any stopped EC2 instances under the autoscaling group.
  def start_instances
    started = 0
    autoscaling_instances.each do |instance|
      ec2_instance = instance.ec2_instance
      next if !ec2_instance.exists?

      if ec2_instance.status == :stopped
        @task.unsafe("Starting instance #{instance.instance_id}") do
          ec2_instance.start
          load_balancers.each do |elb|
            elb.instances.register(instance.instance_id)
          end
          started += 1
        end
      else
        @task.debug { "Instance #{instance.instance_id} already running" }
      end
    end

    # FIXME
    # This is to give instances a little more time to start up and become
    # healthy before restarting autoscaling processes.
    # If an instance isn't started and healthy in time, the autoscale will kill
    # it for being unhealthy.
    #
    # The "right" way to do it would be to actually poll the instances until
    # they are healthy (or a timeout is reached). With the current task model,
    # other actions are blocked while this is waiting, so I can't afford to
    # wait too long.
    sleep(@grace_period) if started > 0
  end

  private

  # AWS::AutoScaling object
  def aws_autoscaling
    @aws_autoscaling ||= AWS::AutoScaling.new(@task.aws_config)
  end

  # AWS::AutoScaling::Group object
  def autoscaling_group
    @autoscaling_group ||= aws_autoscaling.groups[@name]
  end

  # AWS::EC2::Instance objects contained by the scaling group.
  def autoscaling_instances
    autoscaling_group.auto_scaling_instances
  end

  def load_balancers
    autoscaling_group.load_balancers
  end
end
