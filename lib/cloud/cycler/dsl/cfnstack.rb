require 'yaml'

class Cloud::Cycler::DSL::CFNStack
  def initialize(name)
    @name = name
  end

  def stop
    cfn = AWS::CloudFormation.new
    stack = cfn.stacks[@name]
    open("cfn-#{name}.template", 'w') do |io|
      io.write stack.template
    end

    open("cfn-#{name}.params", 'w') do |io|
      io.write stack.params.to_yaml
    end
  end
end
