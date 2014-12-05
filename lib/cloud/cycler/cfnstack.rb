require 'json'
require 'cloud/cycler/namespace'

# Wrapper around AWS::CloudFormation. Provides a public interface compatible
# with Cloud::Cycler::DSL::EC2Interface.
class Cloud::Cycler::CFNStack
  def initialize(task, name)
    @task   = task
    @name   = name
  end

  def start(action)
    case action
    when :default, :start
      if started?
        @task.debug  "#{@name} already started - checking scale up" }
        scale_up
      else
        rebuild
      end
    when :scale_down
      scale_up
    else
      raise Cloud::Cycler::TaskFailure.new("Unrecognised cloudformation action #{action}")
    end
  end

  def stop(action)
    case action
    when :default, :stop
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

  def rebuild_safe?
    tmpl = JSON.parse(cf_stack.template)
    db_instances = rds_instances_from(resources)
    if !db_instances.empty
      if db_instances.size > 1
        @task.warn { "RDS snapshot rebuild not supported for multiple DBInstances" }
        return false
      elsif @task.rds_snapshot_parameter.nil?
        @task.warn { "DBInstances present but no rds_snapshot_parameter present" }
        return false
      elsif tmpl.fetch('Parameters', {}).has_key? @task.rds_snapshot_parameter
        @task.warn { "DBInstances present but template doesn't accept #{@task.rds_snapshot_parameter}" }
        return false
      end
    end

    ec2_instances = ec2_instances_from(resources)
    if !ec2_instances.empty?
      @task.warn { "EBS backed EC2 instances not safe to rebuild" }
      return false
    end

    true
  end

  # (Re)start a stack from saved template + parameters
  def rebuild
    if cf_stack.exists?
      @task.debug { "Stack #{@name} already running (noop)"}
    else
      template, params, resources = load_from_s3(@task.bucket)

      db_instances = rds_instances_from(resources)
      if !db_instances.nil? && @task.rds_snapshot_parameter
        if db_instances.size > 1
          raise Cloud::Cycler::TaskFailure.new("Cannot use rds_snapshot_parameter with multiple DBInstances")
        end

        if db_instances.size == 1
          db_instance_id  = db_instances.first

          snapshot_id = latest_rds_snapshot_of(db_instance_id)
          unless snapshot_id.nil?
            @task.debug { "Setting parameter #{@task.rds_snapshot_parameter} to #{snapshot_id}" }
            params[@task.rds_snapshot_parameter] = snapshot_id
          end
        end
      end

      @task.unsafe("Building stack #{@name}") do
        cf_stacks.create(@name, template, :parameters => params)
      end
    end
  end

  # Stopping a CloudFormation stack involves saving the template and
  # parameters, then deleting the stack.
  def delete
    if cf_stack.exists?
      @task.unsafe("Tearing down stack #{@name}") do
        save_to_s3(@task.bucket)
        cf_stack.delete
      end
    else
      @task.debug { "Stack #{@name} already stopped (noop)" }
    end
  end

  # Checks for any autoscale groups created by the stack, and changes their
  # min/max instances to zero.
  def scale_down
    autoscale = AWS::AutoScaling.new(:region => @task.region)
    cf_stack.resources.each do |resource|
      next unless resource.resource_type == 'AWS::AutoScaling::AutoScalingGroup'

      scale_group = autoscale.groups[resource.physical_resource_id]
      if scale_group.min_size == 0 && scale_group.max_size == 0
        @task.debug { "Stack #{@name} scale group #{scale_group.name} already zeroed" }
        next
      end

      @task.unsafe("Change autoscale #{resource.physical_resource_id} to zero") do
        s3_object = s3_bucket.objects["cloudformation/#{@name}/autoscale/#{scale_group.name}.json"]
        s3_object.write JSON.generate(
          :min_size         => scale_group.min_size,
          :max_size         => scale_group.max_size,
          :desired_capacity => scale_group.desired_capacity
        )
        scale_group.update(:min_size => 0, :max_size => 0, :desired_capacity => 0)
      end
    end
  end

  def scale_up
    autoscale = AWS::AutoScaling.new(:region => @task.region)
    needs_update = false
    cf_stack.resources.each do |resource|
      next unless resource.resource_type == 'AWS::AutoScaling::AutoScalingGroup'

      scale_group = autoscale.groups[resource.physical_resource_id]
      unless scale_group.min_size == 0 && scale_group.max_size == 0
        @task.debug { "Stack #{@name} scale group #{scale_group.name} already unzeroed" }
        next
      end

      @task.unsafe("Reset autoscale #{resource.physical_resource_id} to previous values") do
        s3_object = s3_bucket.objects["cloudformation/#{@name}/autoscale/#{scale_group.name}.json"]
        config = JSON.parse(s3_object.read)
        scale_group.update :min_size         => config['min_size'],
                           :max_size         => config['max_size'],
                           :desired_capacity => config['desired_capacity']
      end
    end
  end

  # True if the stack exists
  def started?
    cf_stack.exists?
  end

  # Save template and parameters to an S3 bucket
  # Bucket may be created if it doesn't exist
  def save_to_s3(bucket_name)
    unless s3_bucket.exists?
      raise Cloud::Cycler::TaskFailure.new("Cannot save #{@name} to non-existant bucket #{s3_bucket.name}")
    end

    template  = cf_stack.template
    params    = cf_stack.parameters
    resources = cf_resources

    @task.unsafe("Writing #{@name} to bucket #{s3_bucket.name}") do
      s3_object("#{@name}/template.json").write(template)
      s3_object("#{@name}/parameters.json").write(params.to_json)
      s3_object("#{@name}/resources.json").write(resources.to_json)
    end
  end

  # Load template and parameters that were previously saved to an S3 bucket
  def load_from_s3(bucket)
    unless s3_bucket.exists?
      raise Cloud::Cycler::TaskFailure.new("Cannot load #{@name} from non-existant bucket #{s3_bucket.name}")
    end

    template  = s3_object("#{@name}/template.json")
    params    = s3_object("#{@name}/parameters.json").read
    resources = s3_object("#{@name}/resources.json").read
    return template, JSON.parse(params), JSON.parse(resources)
  end

  # Recreate the stack, supplying the S3 URL to the API. This overcomes
  # problems passing very large templates as parameters to API calls.
  def restore_from_s3(bucket)
    bucket = s3_bucket

    unless bucket.exists?
      raise Cloud::Cycler::TaskFailure.new("Cannot load #{@name} from non-existant bucket #{s3_bucket.name}")
    end

    template  = s3_object("#{@name}/template.json")
    params    = s3_object("#{@name}/parameters.json").read
    resources = s3_object("#{@name}/resources.json").read
    cf_stacks.create(@name, template, :parameters => JSON.parse(params))
  end

  private

  def latest_rds_snapshot_of(db_instance_id)
    rds = AWS::RDS.new(:region => @task.region)
    candidate = nil
    rds.snapshots.each do |snap|
      next unless snap.snap.db_instance_id == db_instance_id

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

    cf = AWS::CloudFormation.new(:region => @task.region)
    @cf_stacks = cf.stacks
  end

  # A hash representation of resources created by the stack.
  # In the form of { type => [resource-id] }
  # AWS::CloudFormation::Stack is a special case:
  # { AWS::CloudFormation::Stack => { substack-name => substack-resources }}
  def cf_resources
    @cf_resources ||= cf_resources_of(cf_stack)
  end

  def cf_resources_of(stack)
    resources = Hash.new {|h,k| h[k] = [] }
    resources['AWS::CloudFormation::Stack'] = {}

    stack.resources.each do |resource|
      type = resource.resource_type
      id   = resource.physical_resource_id

      if type == 'AWS::CloudFormation::Stack'
        substack = cf_stacks[resource.stack_name]
        resources['AWS::CloudFormation::Stack'][substack.name] = cf_resources_of(substack)
      else
        resources[type].push(id)
      end
    end

    resources
  end

  def rds_instances_from(resources)
    instances = resources['AWS::RDS::DBInstance'] || []
    resources['AWS::CloudFormation::Stack'].each do |substack, substack_resources|
      instances += rds_instances_from(substack_resources)
    end
    instances
  end

  def ec2_instances_from(resources)
    instances = resources['AWS::EC2::Instance'] || []
    resources['AWS::CloudFormation::Stack'].each do |substack, substack_resources|
      instances += ec2_instances_from(substack_resources)
    end
    instances
  end

  def s3_bucket
    return @s3_bucket if defined? @s3_bucket

    s3 = AWS::S3.new(:region => @task.region)
    @s3_bucket = s3.buckets[@task.bucket]
  end

  def s3_object(path)
    real_path = nil
    if @task.bucket_prefix.nil? || @task.bucket_prefix.empty?
      real_path = "cloudformation/#{path}"
    elsif @task.bucket_prefix.end_with? '/'
      real_path = @task.bucket_prefix + "cloudformation/#{path}"
    else
      real_path = "#{@task.bucket_prefix}/cloudformation/#{path}"
    end

    s3_bucket.objects[real_path]
  end
end
