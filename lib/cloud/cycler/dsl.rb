require 'cloud/cycler'

class Cloud::Cycler::DSL
  require 'cloud/cycler/dsl/schedule'
  require 'cloud/cycler/dsl/task'

  attr_accessor :logger
  attr_reader   :catalog

  def initialize(region)
    @region = region
  end

  def run(&block)
    instance_eval(&block)
  end

  def log_to(log_dest)
    @logger = Logger.new(log_dest)
    @logger.formatter = proc do |sev, time, prog, msg|
      "#{time} [#{sev}] #{prog} - #{msg}\n"
    end
  end

  def task(name, &block)
    task = Task.new(@logger, @region, name)
    task.instance_eval(&block)
  end

  def without_tag(tag)
    # TODO
  end

  def with_tag(tag, &block)
    if @features[:ec2]
      ec2 = AWS::EC2.new(:region => @region)
      collection = TaggedCollection.new(self, tag, ec2.instances.tagged(tag))
      collection.instance_eval(&block)
    end

    if @features[:rds]
      rds = AWS::RDS.new(:region => @region)
      collection = TaggedCollection.new(self, tag, rds.db_instances.tagged(tag))
    end
  end
end 
