MockCFResource = Struct.new(:resource_type, :physical_resource_id)
MockCFOutput   = Struct.new(:key, :value)

class MockStack
  attr_accessor :stack_name
  attr_accessor :exists
  attr_accessor :status

  attr_reader :delete_called

  def initialize(stack_name)
    @stack_name = stack_name
    @exists     = true
    @status     = 'CREATE_COMPLETE'
  end

  def delete
    @delete_called = true
  end

  def exists?
    @exists
  end

  def template
    %{
      {
        "Parameters": [
        ]
      }
    }
  end

  def parameters
    {}
  end

  def outputs
    @outputs ||= [
      MockCFOutput.new('Ec2SecurityGroup', 'sg-12345678')
    ]
  end

  def resources
    @resources ||= [
      MockCFResource.new('AWS::IAM::Role', 'test-stack-IamRole'),
      MockCFResource.new('AWS::SNS::Topic', 'arn:aws:sws:test-stack-ScalingNotificationTopic'),
      MockCFResource.new('AWS::EC2::SecurityGroup', 'sg-12345678')
    ]
  end
end

class MockStackCollection
  def initialize
    @stacks = {}
    @created = []
  end

  def [](name)
    @stacks[name] ||= MockStack.new(name)
  end

  def create(name, *args)
    @created.push(name)
  end

  def has_created?(name)
    @created.include? name
  end
end
