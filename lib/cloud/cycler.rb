require 'cloud'
require 'aws-sdk'
require 'logger'

class Cloud::Cycler
  attr_accessor :logger

  def initialize(region)
    @region = region
    @logger = nil
  end

  def self.run(region, &block)
    dsl = DSL.new(region)
    dsl.run(&block)
  end
end
