class MockInstanceCollection
  def [](instance_id)
    @mock_instance ||= MockInstance.new(instance_id)
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
