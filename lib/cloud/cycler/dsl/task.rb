class Cloud::Cycler::DSL::Task
  require 'cloud/cycler/schedule'

  def initialize(log, region, name)
    @log        = log
    @region     = region
    @name       = name
    @catalog    = {}
    @schedule   = nil
    @ec2_action = nil
  end

  def run(&block)
    instance_eval(&block)

    if @schedule.active?
      debug { "Schedule #{schedule} - in hours"}
    else
      debug { "Schedule #{schedule} - out of hours"}
    end
  end

  def region(region)
    @region = region
  end

  def ec2_instances(*instance_ids)
    instance_ids.each do |instance_id|
      @catalog[instance_id] = :ec2_instance
    end
  end

  def ec2_instances_tagged(tags)
    tags.each do |tag, value|
      @catalog["#{tag}:#{value}"] = :tag
    end
  end

  def cloudformation_stack(*names)
    cf = AWS::CloudFormation.new(:region => @region)
    names.each do |name|
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
