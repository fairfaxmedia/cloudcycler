class MockTask
  attr_accessor :rds_snapshot_parameter

  def initialize(unsafe = true)
    @unsafe = unsafe
  end

  def unsafe(message, &block)
    if @unsafe
      block.call
    end
  end

  def bucket
    "fake-s3-bucket"
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
