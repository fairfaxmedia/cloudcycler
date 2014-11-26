# A Cloud Cycler task takes a defined list of resources and a schedule and
# turns them off during 'off' hours and restarts them during 'on' hours.
class Cloud::Cycler::DSL::Task
  require 'cloud/cycler/schedule'
  require 'cloud/cycler/dsl/ec2instance'
  require 'cloud/cycler/dsl/cfnstack'

  attr_reader :region        # Default AWS region
  attr_reader :bucket        # Default S3 bucket
  attr_reader :bucket_prefix # Default S3 bucket

  # Create a new task with a reference to a Cloud::Cycler::DSL application and
  # a task name.
  def initialize(dsl, name)
    @dsl           = dsl
    @region        = dsl.region
    @bucket        = dsl.bucket
    @bucket_prefix = dsl.bucket_prefix
    @name          = name
    @catalog       = {}
    @blacklist     = Hash.new {|h,k| h[k] = [] }
    @schedule      = nil
    @cf_action     = :default
  end

  # Convenience method. Defers to the logger of the parent Cloud::Cycler::DSL.
  def logger
    @dsl.logger
  end

  # The provided block should define the resources and the schedule. Afterwards
  # the defined resources will be either stopped or started, per the schedule.
  def run(&block)
    instance_eval(&block)

    if @schedule.nil?
      warn { "No schedule provided" }
      return
    elsif @schedule.active?
      debug { "Schedule \"#{@schedule}\" - in hours"}
      @catalog.each do |id, obj|
        obj.start
      end
    else
      debug { "Schedule \"#{@schedule}\" - out of hours"}
      @catalog.each do |id, obj|
        obj.stop
      end
    end
  end

  # Overwrite the default region provided by the parent application
  def use_region(region)
    @region = region
  end

  # Overwrite the default S3 bucket provided by the parent application
  def use_bucket(bucket)
    @bucket = bucket
  end

  def use_bucket_prefix(prefix)
    @bucket_prefix = prefix
  end

  # Provide a list of EC2 instances by instance id to be cycled.
  def ec2_instances(*instance_ids)
    instance_ids.each do |instance_id|
      next if @blacklist[:ec2].include? instance_id
      @catalog[instance_id] = Cloud::Cycler::DSL::EC2Instance.new(self, instance_id)
    end
  end

  # Provide a Hash of tag/value pairs to search for. Every EC2 instance that
  # matches at least one of the supplied tag/value pairs will be cycled.
  def ec2_instances_tagged(tags)
    tags.each do |tag, value|
      ec2 = AWS::EC2.new(:region => @region)
      ec2.instances.with_tag(tag, value).each do |instance|
        instance_id = instance.instance_id
        next if @blacklist[:ec2].include? instance_id
        @catalog[instance_id] = Cloud::Cycler::DSL::EC2Instance.new(self, instance_id)
      end
    end
  end

  # Blacklist ec2 instances to be excluded from pattern matching, etc.
  def ec2_blacklist(*instance_ids)
    instance_ids.each do |instance_id|
      @catalog.delete(instance_id)
      @blacklist[:ec2].push instance_ids
    end
  end

  # A list of cloudformation stacks to be cycled.
  def cloudformation_include(*names)
    names.each do |name|
      next if @blacklist[:cfn].include? name
      if name.is_a? Regexp
        stack_cache.each do |stack_name|
          if stack_name.match(name)
            @catalog[stack_name] = Cloud::Cycler::DSL::CFNStack.new(self, stack_name)
          end
        end
      else
        @catalog[name] = Cloud::Cycler::DSL::CFNStack.new(self, name)
      end
    end
  end

  # Blacklist cloudformation stacks to be excluded from pattern matching, etc.
  def cloudformation_exclude(*names)
    names.each do |name|
      @catalog.delete(name)
      @blacklist[:cfn].push name
    end
  end

  # Defines the schedule for the task.
  def schedule(spec)
    @schedule = Cloud::Cycler::Schedule.parse(spec)
  end

  def cf_action(action)
    @cf_action = action
  end

  def get_cf_action
    @cf_action
  end

  # Runs the block only if the application is NOT in dryrun mode.
  def unsafe(message)
    if @dsl.dryrun
      info { "noop - #{message}" }
    else
      info { message }
      yield
    end
  end

  # Convenience method for debug logging
  def debug(&block)
    if @dsl.logger
      @dsl.logger.debug("task:#{@name}", &block)
    end
  end

  # Convenience method for info logging
  def info(&block)
    if @dsl.logger
      @dsl.logger.info("task:#{@name}", &block)
    end
  end

  # Convenience method for warning logging
  def warn(&block)
    if @dsl.logger
      @dsl.logger.warn("task:#{@name}", &block)
    end
  end

  private

  def stack_cache
    return @stack_cache if defined? @stack_cache
    @stack_cache = []
    cf = AWS::CloudFormation.new(:region => @region)
    cf.stacks.each do |stack|
      @stack_cache.push stack.name
    end
    s3 = AWS::S3.new(:region => @region)
    bucket = s3.buckets[@bucket]

    cf_prefix = nil
    if @bucket_prefix.nil? || @bucket_prefix.empty?
      cf_prefix = 'cloudformation'
    elsif @bucket_prefix.end_with? '/'
      cf_prefix = @bucket_prefix + 'cloudformation'
    else
      cf_prefix = "#{@bucket_prefix}/cloudformation"
    end

    bucket.objects.with_prefix(cf_prefix).each do |object|
      folders = object.key.split('/').drop_while {|folder| folder != 'cloudformation' }
      @stack_cache.push(folders[1])
    end
    @stack_cache = @stack_cache.sort.uniq
  end
end
