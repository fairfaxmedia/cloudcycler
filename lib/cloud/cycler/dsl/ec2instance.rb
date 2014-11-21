class Cloud::Cycler::DSL::EC2Instance
  def initialize(instance_id)
    @instance_id = instance_id
  end

  def stop
    ec2 = AWS::EC2.new
    instance = ec2.instances[@instance_id]
    if instance.status == :running
      instance.stop
    end
  end

  def start
    ec2 = AWS::EC2.new
    instance = ec2.instances[@instance_id]
    if instance.status == :stopped
      instance.start
    end
  end
end
