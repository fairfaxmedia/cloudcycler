
class MockCycler
  attr_accessor :region
  attr_accessor :bucket
  attr_accessor :bucket_prefix
  attr_accessor :bucket_region

  def initialize
    @region = 'dummy-1'
    @bucket = 's3-dummy'

    @bucket_region = 'dummy-1'
  end

  def aws_max_retries
    5
  end
end
