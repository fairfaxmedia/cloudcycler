require 'minitest/autorun'
require 'cloud/cycler/ec2instance'

module AWS
  module EC2
    module Errors
      InvalidInstanceID = Class.new(StandardError)
    end
  end
end

class MockTask
  def initialize(unsafe = true)
    @unsafe = unsafe
  end

  def unsafe(message, &block)
    if @unsafe
      block.call
    end
  end

  def debug(&block)
  end

  def info(&block)
  end
  
  def warn(&block)
  end

  def region
    'dummy-region'
  end
end

class MockInstance
  attr_accessor :instance_id
  attr_accessor :status
  attr_accessor :exists

  attr_reader :start_called
  attr_reader :stop_called

  def initialize(instance_id)
    @instance_id = instance_id
    @exists      = true
  end  

  def start
    @start_called = true
  end

  def stop
    @stop_called = true
  end

  def exists?
    true
  end
end

class MockInstanceCollection
  def [](instance_id)
    @mock_instance ||= MockInstance.new(instance_id)
  end
end

class TestEC2Instance < Minitest::Unit::TestCase
  def test_safe_start_stopped_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(false), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :stopped

      instance.start
      assert !mock_instance.start_called
    end
  end

  def test_unsafe_start_stopped_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(true), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :stopped

      instance.start
      assert mock_instance.start_called
    end
  end

  def test_safe_start_running_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(false), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :running

      instance.start
      assert !mock_instance.start_called
    end
  end

  def test_unsafe_start_running_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(true), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :running

      instance.start
      assert !mock_instance.start_called
    end
  end

  def test_safe_stop_stopped_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(false), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :stopped

      instance.stop
      assert !mock_instance.stop_called
    end
  end

  def test_unsafe_stop_stopped_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(true), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :stopped

      instance.stop
      assert !mock_instance.stop_called
    end
  end

  def test_safe_stop_running_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(false), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :running

      instance.stop
      assert !mock_instance.stop_called
    end
  end

  def test_unsafe_stop_running_instance
    instance = Cloud::Cycler::EC2Instance.new(MockTask.new(true), 'i-deadbeef')
    collection = MockInstanceCollection.new
    instance.stub(:ec2_instances, collection) do
      mock_instance = collection['i-deadbeef']
      mock_instance.status = :running

      instance.stop
      assert mock_instance.stop_called
    end
  end
end
