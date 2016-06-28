require 'minitest/autorun'
require 'cloud/cycler/asgroup'
require 'cctest'

class MockAutoScalingInstance
  attr_reader :start_called, :stop_called, :terminate_called
  attr_reader :status
  attr_reader :instance_id

  def initialize(id)
    @instance_id = id
    @status      = :stopped
  end

  def ec2_instance
    self
  end

  def start
    @start_called = true
  end

  def stop
    @stop_called = true
  end

  def terminate
    @terminate_called = true
  end

  def exists?
    true
  end
end

class MockAWSAutoScaling
  def groups
    @groups ||= MockAutoScalingGroupCollection.new
  end
end

class MockAutoScalingGroupCollection
  def initialize
    @groups = Hash.new {|h,k| h[k] = MockAutoScalingGroup.new(k) }
  end

  def [](key)
    @groups[key]
  end
end

class MockAutoScalingGroup
  Processes = %w(Launch Terminate HealthCheck ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions AddToLoadBalancer)
  attr_accessor :suspended_processes

  def initialize(name, num = 1)
    @name                = name
    @num                 = num
    @suspended_processes = Processes
  end

  def exists?
    true
  end

  def auto_scaling_instances
    @auto_scaling_instances ||= @num.times.map do |n|
      MockAutoScalingInstance.new("#{@name}-#{n+1}")
    end
  end

  def suspend_processes(to_suspend)
    @suspended_processes = (@suspended_processes + [to_suspend].flatten).uniq
  end

  def resume_processes(to_resume)
    @suspended_processes = (@suspended_processes - to_resume)
  end

  def suspend_all_processes
    @suspended_processes = Processes
  end

  def resume_all_processes
    @suspended_processes = []
  end

  def load_balancers
    if @load_balancer.nil?
      @load_balancer = MockLoadBalancer.new
      @load_balancer.registered = auto_scaling_instances.map(&:instance_id)
    end
    [@load_balancer]
  end
end

class MockLoadBalancer
  attr_accessor :registered
  attr_accessor :deregistered

  def initialize
    @registered   = []
    @deregistered = []
  end

  def instances
    MockLoadBalancerInstancesCollection.new(self)
  end

  def register(instance_id)
    @registered << instance_id
  end

  def deregister(instance_id)
    @deregistered << instance_id
  end
end

class MockLoadBalancerInstancesCollection
  def initialize(lb)
    @lb = lb
  end

  def register(instance_id)
    @lb.registered << instance_id
  end

  def deregister(instance_id)
    @lb.deregistered << instance_id
  end
end

class TestASGroup < Minitest::Test
  def test_safe_start_stopped_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.load_balancers.each do |elb|
        elb.registered = []
      end

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.auto_scaling_instances.none? {|x| x.start_called },
          'Autoscaling instances started'
        )
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.none? do |elb|
              elb.registered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances registered to ELB'
        )
      end
    end
  end

  def test_safe_stop_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:stop)
        assert(mock_group.auto_scaling_instances.none? {|x| x.stop_called })
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.registered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not registered to ELB'
        )
      end
    end
  end

  def test_safe_terminate_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(false), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:terminate)
        assert(mock_group.auto_scaling_instances.none? {|x| x.terminate_called })
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.registered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not registered to ELB'
        )
      end
    end
  end

  def test_unsafe_start_stopped_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.suspended_processes.empty?,
          'Autoscaling group processes not resumed'
        )
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.start_called },
          'Autoscaling instances not started'
        )
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.registered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not registered to ELB'
        )
      end
    end
  end

  def test_unsafe_start_terminated_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']

      group.stub(:autoscaling_group, mock_group) do
        group.start
        assert(
          mock_group.suspended_processes.empty?,
          'Autoscaling group processes not resumed'
        )
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.registered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not registered to ELB'
        )
      end
    end
  end

  def test_unsafe_stop_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:stop)
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.stop_called },
          'Autoscaling instances not stopped'
        )
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.deregistered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not deregistered from ELB'
        )
      end
    end
  end

  def test_unsafe_terminate_started_group
    group = Cloud::Cycler::ASGroup.new(MockTask.new(true), 'as-12345')
    group.grace_period = 0

    aws_autoscaling = MockAWSAutoScaling.new

    group.stub(:aws_autoscaling, aws_autoscaling) do
      mock_group = aws_autoscaling.groups['as-12345']
      mock_group.suspended_processes = []

      group.stub(:autoscaling_group, mock_group) do
        group.stop(:terminate)
        assert(
          mock_group.auto_scaling_instances.all? {|x| x.terminate_called },
          'Autoscaling instances not terminated'
        )
        assert(
          mock_group.auto_scaling_instances.all? do |inst|
            mock_group.load_balancers.all? do |elb|
              elb.deregistered.include?(inst.instance_id)
            end
          end,
          'Autoscaling instances not deregistered from ELB'
        )
      end
    end
  end
end
