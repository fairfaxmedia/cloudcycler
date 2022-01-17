require 'json'
require 'cloud/cycler/namespace'
require 'cloud/cycler/asgroup'
require 'cloud/cycler/ec2instance'

# Wrapper around AWS::CloudFormation. Provides a public interface compatible
# with Cloud::Cycler::DSL::EC2Interface.
class Cloud::Cycler::CFNStack
  def initialize(task, name)
    @task   = task
    @name   = name
  end

  # Start the stack (if necessary)
  # This will rebuild a stack or scale one back up, as necessary
  def start(action)
    if cf_stack.exists?
      status = cf_stack.status
      if status =~ /_FAILED$/
        @task.warn { "Ignoring stack #{@name} - status is #{status}" }
        return
      end
    end

    case action
    when :default, :start, :terminate
      if cf_stack.exists?
        @task.debug { "#{@name} already started - checking scale up" }
        scale_up
      else
        rebuild
      end
    when :scale_down
      if !cf_stack.exists?
        @task.warn { "#{@name} doesn't exist - cannot scale down" }
      else
        scale_up
      end
    else
      raise Cloud::Cycler::TaskFailure.new("Unrecognised cloudformation action #{action}")
    end
  end

  # Stop a stack (if necessary).
  # Checks if the stack is safe to tear down (via #rebuild_safe?), and falls
  # back to scaling down ec2 otherwise.
  def stop(action)
    if !cf_stack.exists?
      @task.debug { "#{@name} already suspended" }
      return
    end

    status = cf_stack.status
    if status =~ /_FAILED$/
      @task.warn { "Ignoring stack #{@name} - status is #{status}" }
      return
    end

    case action
    when :default, :stop, :terminate
      if rebuild_safe?
        delete
      else
        @task.info { "Stack #{@name} not safe to rebuild, scaling down instead" }
      end
    when :scale_down
      scale_down
    else
      raise Cloud::Cycler::TaskFailure.new("Unrecognised cloudformation action #{action}")
    end
  end

  # Runs a few heuristics to determine if the stack appears to be safe to tear down.
  # This helps to avoid data loss from deleting something that can't be restored.
  def rebuild_safe?
    tmpl = JSON.parse(cf_stack.template)
    db_instances = rds_instances_from(cf_resources)
    if !db_instances.empty?
      if db_instances.size > 1
        @task.warn { "RDS snapshot rebuild not supported for multiple DBInstances" }
        return false
      elsif @task.rds_snapshot_parameter.nil?
        @task.warn { "DBInstances present but no rds_snapshot_parameter present" }
        return false
      elsif !tmpl.fetch('Parameters', {}).has_key?(@task.rds_snapshot_parameter)
        @task.warn { "DBInstances present but template doesn't accept #{@task.rds_snapshot_parameter}" }
        return false
      end
    end

    # TODO: figure out how to handle static EC2 resources
    ec2_instances = ec2_instances_from(cf_resources)
    if !ec2_instances.empty?
      @task.warn { "EBS backed EC2 instances not safe to rebuild" }
      return false
    end

    # Check that this stack isn't linked to another stack in some way. Ordering
    # of teardown and rebuilds is currently unsupported. This might require
    # running as a daemon, since we will need to wait quite a while for stacks
    # to delete/build.
    dep_info = @task.cfn_dependencies(@name)
    if dep_info
      if dep_info['child_of']
        @task.warn { "Stack #{@name} is a substack of #{dep_info['child_of']}" }
        return false
      elsif !dep_info['needs'].empty? || !dep_info['feeds'].empty?
        @task.warn { "Stack #{@name} has interdependencies with other stacks" }
        return false
      end
    end

    true
  end

  # (Re)start a stack from saved template + parameters
  def rebuild
    if cf_stack.exists?
      @task.debug { "Stack #{@name} already running (noop)"}
      return
    end
    template, params, resources = load_from_s3(@task.bucket)

    db_instances = rds_instances_from(resources)
    if !db_instances.nil? && @task.rds_snapshot_parameter
      if db_instances.size > 1
        # This probably shouldn't happen, but if it does it might require
        # manual intervention to make sure the stack is rebuild properly.
        raise Cloud::Cycler::CycleFailure.new("Failed to rebuild stack #{@name} with #{db_instances.size} RDS instances")
      end

      if db_instances.size == 1
        db_instance_id = db_instances.first

        snapshot_id = latest_rds_snapshot_of(db_instance_id)
        unless snapshot_id.nil?
          @task.debug { "Setting parameter #{@task.rds_snapshot_parameter} to #{snapshot_id}" }
          params[@task.rds_snapshot_parameter] = snapshot_id
        end
      end
    end

    @task.unsafe("Building stack #{@name}") do
      tags = [ {
        key: "Creator",
        value: "Cloudcycler"
      } ]
      cf_stacks.create(@name, template, :parameters => params, :tags = tags)
    end
  rescue AWS::S3::Errors::NoSuchKey
    @task.warn { "Cannot rebuild #{@name} - No details in S3" }
  end

  # Stopping a CloudFormation stack involves saving the template and
  # parameters, then deleting the stack.
  def delete
    if cf_stack.exists?
      db_instances = rds_instances_from(cf_resources)
      db_instances.each do |db_instance_id|
        rds = AWS::RDS.new(@task.aws_config)
        rds.instances[db_instance_id]
        snapshot_id = Time.now.strftime("#{db_instance_id}-cc-%Y-%m-%d-%H-%M")
        db_instance.create_snapshot(snapshot_id)
      end
      @task.unsafe("Tearing down stack #{@name}") do
        save_to_s3(@task.bucket)
        cf_stack.delete
      end
    else
      @task.debug { "Stack #{@name} already stopped (noop)" }
    end
  end

  # If it's not safe to delete/rebuild the stack, then scan the list of
  # resources and stop them individually.
  def scale_down
    instances = ec2_instances_from(cf_resources)
    instances.each do |instance_id|
      Cloud::Cycler::EC2Instance.new(@task, instance_id).stop
    end

    autoscale = AWS::AutoScaling.new(@task.aws_config)
    groups = autoscale_groups_from(cf_resources)
    groups.each do |id, params|
      Cloud::Cycler::ASGroup.new(@task, id).stop(@task.actions[:autoscaling])
    end
  end

  # Scan the list of stack resources, and make sure they are all started.
  def scale_up
    instances = ec2_instances_from(cf_resources)
    instances.each do |instance_id|
      Cloud::Cycler::EC2Instance.new(@task, instance_id).start
    end

    groups = autoscale_groups_from(cf_resources)
    groups.each do |id, params|
      Cloud::Cycler::ASGroup.new(@task, id).start
    end
  end

  # Save template and parameters to an S3 bucket
  # Bucket may be created if it doesn't exist
  def save_to_s3(bucket_name)
    template  = cf_stack.template
    params    = cf_stack.parameters
    resources = cf_resources
    outputs   = cf_outputs

    @task.unsafe("Writing #{@name} to bucket #{s3_bucket.name}") do
      s3_object("template.json").write(template)
      s3_object("parameters.json").write(params.to_json)
      s3_object("resources.json").write(resources.to_json)
      s3_object("outputs.json").write(outputs.to_json)
    end
  end

  # Load template and parameters that were previously saved to an S3 bucket
  def load_from_s3(bucket)
    template  = s3_object("template.json")
    params    = s3_object("parameters.json").read
    resources = s3_object("resources.json").read
    return template, JSON.parse(params), JSON.parse(resources)
  end

  private

  # Find the latest RDS snapshot taken from a given DB instance name
  def latest_rds_snapshot_of(db_instance_id)
    rds = AWS::RDS.new(@task.aws_config)
    candidate = nil
    rds.snapshots.each do |snap|
      next unless snap.db_instance_id == db_instance_id

      if candidate.nil? || candidate.created_at < snap.created_at
        candidate = snap
      end
    end
    candidate.nil? ? nil : candidate.id
  end

  # Memoization for the AWS::CloudFormation::Stack object
  def cf_stack
    @cf_stack ||= cf_stacks[@name]
  end

  # Memoization for the AWS::CloudFormation object
  def cf_stacks
    return @cf_stacks if defined? @cf_stacks

    cf = AWS::CloudFormation.new(@task.aws_config)
    @cf_stacks = cf.stacks
  end

  # Fetch the stack outputs, and convert to a Hash
  def cf_outputs
    return @cf_outputs if defined? @cf_ouputs
    @cf_outputs = {}

    cf_stack.outputs.each do |out|
      @cf_outputs[out.key] = out.value
    end

    @cf_outputs
  end

  # A hash representation of resources created by the stack.
  # In the form of { type => [resource-id] }
  # AWS::CloudFormation::Stack is a special case:
  # { AWS::CloudFormation::Stack => { substack-name => substack-resources }}
  def cf_resources
    @cf_resources ||= cf_resources_of(cf_stack)
  end

  # Gather the resource list from a running stack. For master stacks that
  # create substacks as resources, recurse through their resource lists as
  # well.
  def cf_resources_of(stack)
    resources = Hash.new do |h,k|
      if k == 'AWS::CloudFormation::Stack' || k == 'AWS::AutoScaling::AutoScalingGroup'
        h[k] = {}
      else
        h[k] = []
      end
    end

    stack.resources.each do |resource|
      type = resource.resource_type
      id   = resource.physical_resource_id

      if type == 'AWS::CloudFormation::Stack'
        substack = cf_stacks[id]
        resources['AWS::CloudFormation::Stack'][substack.name] = cf_resources_of(substack)
      elsif type == 'AWS::AutoScaling::AutoScalingGroup'
        autoscale = AWS::AutoScaling.new(@task.aws_config)
        scale_group = autoscale.groups[id]
        resources['AWS::AutoScaling::AutoScalingGroup'][id] = {
          :min_size         => scale_group.min_size,
          :max_size         => scale_group.max_size,
          :desired_capacity => scale_group.desired_capacity
        }
      else
        resources[type].push(id)
      end
    end

    resources
  end

  # Scan a resource list for RDS instances
  def rds_instances_from(resources)
    instances = resources['AWS::RDS::DBInstance'] || []
    return instances if resources['AWS::CloudFormation::Stack'].nil?

    resources['AWS::CloudFormation::Stack'].each do |substack, substack_resources|
      instances += rds_instances_from(substack_resources)
    end
    instances
  end

  # Scan a resource list for EC2 instances
  def ec2_instances_from(resources)
    instances = resources['AWS::EC2::Instance'] || []
    resources['AWS::CloudFormation::Stack'].each do |substack, substack_resources|
      instances += ec2_instances_from(substack_resources)
    end
    instances
  end

  # Scan a resource list for EC2 instances
  def autoscale_groups_from(resources)
    groups = resources['AWS::AutoScaling::AutoScalingGroup'] || {}
    resources['AWS::CloudFormation::Stack'].each do |substack, substack_resources|
      groups = groups.merge(autoscale_groups_from(substack_resources))
    end
    groups
  end

  # Memoization for S3 bucket object
  def s3_bucket
    return @s3_bucket if defined? @s3_bucket

    s3 = AWS::S3.new(@task.aws_config)
    @s3_bucket = s3.buckets[@task.bucket]
  end

  # Find an S3 object, prepending the task prefix, stack name, etc to the supplied path.
  def s3_object(path)
    @task.s3_object("cloudformation/#{@name}/#{path}")
  end
end
