class Cloud::Cycler::DSL::Task
  require 'cloud/cycler/schedule'
  require 'cloud/cycler/dsl/ec2instance'

  def initialize(log, region, name)
    @log        = log
    @region     = region
    @name       = name
    @catalog    = {}
    @schedule   = nil
  end

  def run(&block)
    instance_eval(&block)

    if @schedule.nil?
      debug { "No schedule provided" }
      return
    elsif @schedule.active?
      debug { "Schedule \"#{@schedule}\" - in hours"}
      @catalog.each do |id, obj|
        debug { "start #{id}" }
      end
    else
      debug { "Schedule \"#{@schedule}\" - out of hours"}
      @catalog.each do |id, obj|
        debug { "stop #{id}" }
      end
    end
  end

  def region(region)
    @region = region
  end

  def ec2_instances(*instance_ids)
    instance_ids.each do |instance_id|
      @catalog[instance_id] = EC2Instance.new(instance_id)
    end
  end

  def ec2_instances_tagged(tags)
    tags.each do |tag, value|
      ec2 = AWS::EC2.new(:region => @region)
      ec2.instances.with_tag(tag, value).each do |instance|
        instance_id = instance.instance_id
        @catalog[instance_id] = EC2Instance.new(instance_id)
      end
    end
  end

  def cloudformation_stack(*names)
    cfn = AWS::CloudFormation.new(:region => @region)
    names.each do |name|
      cfn.stacks[name]
      @catalog[name] = :cfn_stack
    end
  end

  def schedule(spec)
    @schedule = Cloud::Cycler::Schedule.parse(spec)
  end

  def debug(&block)
    if @log
      @log.debug("task:#{@name}", &block)
    end
  end

  def ec2_action(action)
    @ec2_action = action
  end
end
