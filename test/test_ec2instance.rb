require 'minitest/autorun'
require 'cloud/cycler/ec2instance'
require 'cctest'

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
