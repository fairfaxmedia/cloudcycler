require 'cloud/cycler/namespace'

# A task in cloudcycler is a collection of resources to be scheduled.
# Mostly handles finding the resources and applying include/exclude rules. The
# task level settings can be overwritten with settings in DynamoDB, which is
# handled here.
#
# The task also handles some broader scans such as building a dependency graph
# from CloudFormation outputs and inputs (parameters). The logic against the
# dependency graph is applied in the CFNStack resources though.
class Cloud::Cycler::Task
  require 'cloud/cycler/ec2instance'
  require 'cloud/cycler/cfnstack'
  require 'cloud/cycler/schedule'

  # Since we pass around type = :cfn variables, this allows klass = TYPES[type]
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

  # Add an exclude rule to the list. Exclude object should usually be a String
  # or a Regexp, but may be anything that responds to #===.
  def exclude(type, exclusion)
    @excludes[type].push(exclusion)
    @includes[type].reject! {|id| exclusion === id }
  end

  # Check if an id matches anything in the excludes list
  def excluded?(type, id)
    @excludes[type].any? {|ex| ex === id }
  end

  # Add an exclude rule to the list. Exclude object should usually be a String
  # or a Regexp, but may be anything that responds to #===.
  # TODO: I don't link the per type logic. I need to get cfn_cache and
  # ec2_cache to return data in the same format to consolidate them. cfn_cache
  # needs refactoring first though.
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

  # Process each of the included resources. Looks for settings in dynamodb
  # which overwrite the task settings.
  def run
    check_cfn_dependencies

    @includes.each do |type, ids|
      klass = TYPES[type]
      raise Cloud::Cycler::TaskFailure.new("Unknown type #{type}") if klass.nil?
      ids.each do |id|
        item_schedule = @schedule
        item_excluded = false

        attrs = ddb_attrs(type, id)
        if attrs.has_key? 'schedule'
          item_schedule = Cloud::Cycler::Schedule.parse(attrs['schedule'])
        end
        item_disabled = attrs['status'] == 'disabled' if attrs.has_key? 'status'

        if item_disabled
          debug { "#{type}:#{id} disabled - skipping" }
        elsif item_schedule.nil?
          warn { "#{type}:#{id} has no schedule - cannot process" }
        elsif item_schedule.active?
          debug { "#{type}:#{id} schedule (#{item_schedule}) active" }
          klass.new(self, id).start(@actions[type])
        else
          debug { "#{type}:#{id} schedule (#{item_schedule}) inactive" }
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

  # Another convenience method for when you have type = :cfn variables
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

  # Grabs the hash containing a stacks dependencies and/or parent/child
  # relationships from the list cfn_cache builds.
  def cfn_dependencies(name)
    cfn_cache unless defined? @cfn_cache
    @cfn_cache[:live][name]
  end

  def s3_object(suffix)
    @s3        ||= AWS::S3.new(:region => @region)
    @s3_bucket ||= @s3.buckets[@bucket]

    unless @s3_bucket.exists?
      raise Cloud::Cycler::TaskFailure.new("S3 bucket #{@bucket} does not exist")
    end

    object_path = ''
    if @bucket_prefix.nil? || @bucket_prefix.empty?
      object_path = suffix
    else
      object_path = "#{@bucket_prefix.chomp('/')}/#{suffix}"
    end

    s3_objects[object_path]
  end

  private

  # Lookup per resource settings from DynamoDB
  def ddb_attrs(type, id)
    @ddb       ||= AWS::DynamoDB.new(:region => @region)

    if !defined? @ddb_table
      @ddb_table = @ddb.tables['cloudcycler'] # FIXME - don't hardcode names
      @ddb_table.load_schema
    end

    @ddb_items ||= @ddb_table.items

    item = @ddb_items[type.to_s, id]
    return {} if item.nil?
    item.attributes.to_hash
  end

  # Scan a list of EC2 instances. It would probably be more efficient to use
  # filters in the request, but that doesn't work as well for other AWS
  # technologies and I'd rather keep them all consistent.
  def ec2_cache
    return @ec2_cache if defined? @ec2_cache

    @ec2_cache = {}
    ec2 = AWS::CloudFormation.new(:region => @region)
    ec2.instances.each do |instance|
      @ec2_cache[instance.name] = instance.id
    end

    @ec2_cache
  end

  # Scans a list of active cloudformation stacks, and also a list of stacks
  # that have been "stopped". i.e. have had their details saved to S3 so they
  # can be recreated.
  # While it's scanning all the active stacks, it also checks their outputs,
  # parameters (inputs), and child resources to build a dependency graph.
  # FIXME - This method is getting super-huge. It needs to be broken down into
  # smaller methods. The actual return value should also be changed to make it
  # consistent with e.g. ec2_cache which would allow some of the logic above to
  # be cleaned up.
  def cfn_cache
    return @cfn_cache[:live].keys + @cfn_cache[:saved] if defined? @cfn_cache

    @cfn_cache = {:live => {}, :saved => []}

    links  = Hash.new {|h,k| h[k] = { :src   => [], :dst   => [] } }
    stacks = Hash.new {|h,k| h[k] = { :needs => [], :feeds => [] } }

    cfn = AWS::CloudFormation.new(:region => @region)
    cfn.stacks.each do |stack|
       stacks[stack.name] = {:needs => [], :feeds => [], :children => []}

       stack.outputs.each do |output|
         links[output.value][:src].push(stack.name)
       end

       stack.parameters.each do |param, value|
         links[value][:dst].push(stack.name)
       end

       stack.resources.each do |resource|
         if resource.resource_type == 'AWS::CloudFormation::Stack'
           substack_name = resource.stack_name
           stacks[stack.name][:children].push(substack_name)
           stacks[substack_name][:child_of] = stack.name
         end
       end
    end
    deps = links.reject {|value, data| data[:src].empty? || data[:dst].empty? }

    deps.delete(nil) # TODO - Figure out where these come from
    deps.each do |value, data|
      data[:src].each do |src|
        data[:dst].each do |dst|
          next if src == dst
          stacks[dst][:required_by].push(dst)
          stacks[src][:requires].push(src)
        end
      end
    end

    @cfn_cache[:live] = stacks
    @cfn_dependencies = deps

    s3 = AWS::S3.new(:region => @region)
    bucket = s3.buckets[@bucket]

    cf_prefix = nil
    if @bucket_prefix.nil? || @bucket_prefix.empty?
      cf_prefix = 'cloudformation'
    else
      cf_prefix = "#{@bucket_prefix.chomp('/')}/cloudformation"
    end

    bucket.objects.with_prefix(cf_prefix).each do |object|
      folders = object.key.split('/').drop_while {|folder| folder != 'cloudformation' }
      @cfn_cache[:saved].push(folders[1])
    end
    @cfn_cache = @cfn_cache.sort.uniq
  end
end
