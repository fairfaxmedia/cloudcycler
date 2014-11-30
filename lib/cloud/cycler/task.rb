class Cloud::Cycler::Task
  require 'cloud/cycler/ec2instance'
  require 'cloud/cycler/cfnstack'
  require 'cloud/cycler/schedule'

  TYPES = {
    :ec2 => Cloud::Cycler::EC2Instance,
    :cfn => Cloud::Cycler::CFNStack,
  }

  attr_reader :cycler, :name

  attr_accessor :region
  attr_accessor :bucket
  attr_accessor :bucket_prefix
  attr_accessor :bucket_region
  attr_accessor :includes, :excludes
  attr_accessor :schedule
  attr_accessor :cfn_action
  attr_accessor :ec2_action
  attr_accessor :actions
  attr_accessor :rds_snapshot_parameter

  def initialize(cycler, name)
    @name          = name
    @cycler        = cycler
    @region        = cycler.region
    @bucket        = cycler.bucket
    @bucket_prefix = cycler.bucket_prefix
    @bucket_region = cycler.bucket_region

    @includes = Hash.new {|h,k| h[k] = []}
    @excludes = Hash.new {|h,k| h[k] = []}
    @actions  = Hash.new {|h,k| h[k] = :default}
  end

  def logger
    @cycler.logger
  end

  def exclude(type, exclusion)
    @excludes[type].push(exclusion)
    @includes[type].reject! {|id| exclusion === id }
  end

  def excluded?(type, id)
    @excludes[type].any? {|ex| ex === id }
  end

  def include(type, id)
    case type
    when :cfn
      cfn_cache.each do |stack_name|
        next if excluded?(type, stack_name)
        if id === stack_name
          @includes[type].push(stack_name)
        end
      end
    when :ec2
      ec2_cache.each do |instance_name, instance_id|
        next if excluded?(type, instance_name)
        if id === instance_name
          @includes[type].push(instance_name)
        end
      end
    else
      @includes[type].push(id) unless excluded?(type, id)
    end
  end

  # The provided block should define the resources and the schedule. Afterwards
  # the defined resources will be either stopped or started, per the schedule.
  def run
    if @schedule.nil?
      error { "No schedule provided" }
      return
    elsif @schedule.active?
      debug { "Schedule \"#{@schedule}\" - in hours"}
      @includes.each do |type, ids|
        klass = TYPES[type]
        raise Cloud::Cycler::TaskFailure.new("Unknown type #{type}") if klass.nil?
        ids.each do |id|
          klass.new(self, id).start(@actions[type])
        end
      end
    else
      debug { "Schedule \"#{@schedule}\" - out of hours"}
      @includes.each do |type, ids|
        klass = TYPES[type]
        raise Cloud::Cycler::TaskFailure.new("Unknown type #{type}") if klass.nil?
        ids.each do |id|
          klass.new(self, id).stop(@actions[type])
        end
      end
    end
  end

  # Runs the block only if the application is NOT in dryrun mode.
  def unsafe(message)
    if @cycler.dryrun
      info { "noop - #{message}" }
    else
      info { message }
      yield
    end
  end

  # Convenience method for debug logging
  def debug(&block)
    if @cycler.logger
      @cycler.logger.debug("task:#{@name}", &block)
    end
  end

  # Convenience method for info logging
  def info(&block)
    if @cycler.logger
      @cycler.logger.info("task:#{@name}", &block)
    end
  end

  # Convenience method for warning logging
  def warn(&block)
    if @cycler.logger
      @cycler.logger.warn("task:#{@name}", &block)
    end
  end

  def cache(type)
    case type
    when :cfn
      cfn_cache
    when :ec2
      ec2_cache
    when :rds
      rds_cache
    end
  end

  private

  def ec2_cache
    return @ec2_cache if defined? @ec2_cache

    @ec2_cache = {}
    ec2 = AWS::CloudFormation.new(:region => @region)
    ec2.instances.each do |instance|
      @ec2_cache[instance.name] = instance.id
    end

    @ec2_cache
  end

  def cfn_cache
    return @cfn_cache if defined? @cfn_cache

    @cfn_cache = []
    cf = AWS::CloudFormation.new(:region => @region)
    cf.stacks.each do |stack|
      @cfn_cache.push stack.name
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
      @cfn_cache.push(folders[1])
    end
    @cfn_cache = @cfn_cache.sort.uniq
  end
end
