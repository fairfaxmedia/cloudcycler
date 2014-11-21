class Cloud::Cycler::DSL::Task
  def initialize(log, region, name)
    @log      = log
    @region   = region
    @name     = name
    @catalog  = []
    @schedule = nil
    @actions  = []
  end

  def run(&block)
    instance_eval(&block)
  end

  def region(region)
    @region = region
  end

  def ec2_instances(*instance_ids)
    ec2 = AWS::EC2.new(:region => @region)
    instance_ids.each do |instance_id|
      instance = ec2.instances[instance_id]
      debug { "Adding #{instance.instance_id} to catalog" }
      @catalog.push instance
    end
  end

  def ec2_instances_tagged(tags)
    ec2 = AWS::EC2.new(:region => @region)
    tags.each do |tag, value|
      ec2.instances.with_tag(tag, value).each do |instance|
        debug { "Adding #{instance.instance_id} to catalog" }
        @catalog.push instance
      end
    end
  end

  def cloudformation_stack(*names)
    cf = AWS::CloudFormation.new(:region => @region)
    names.each do |name|
      stack = cf.stacks[name]
      debug { "Adding #{stack.stack_id} to catalog" }
      @catalog.push stack
    end
  end

  def schedule(spec)
    @schedule = spec
  end

  def debug(&block)
    if @log
      @log.debug("task:#{@name}", &block)
    end
  end
end
