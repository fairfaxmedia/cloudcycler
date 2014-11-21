class Cloud::Cycler::DSL::Schedule
  def self.empty
    self.new('----- 0000-0000')
  end

  def initialize(schedule)
    @schedule = schedule
    @actions = {}
  end

  def to_s
     agenda = @actions.map{|k,v| "#{v}:#{k}"}.join(',')
     "#<#{self.class}:#{agenda}>"
  end

  def start(feature)
    @actions[feature] = :start
  end

  def stop(feature)
    @actions[feature] = :stop
  end

  def hibernate(feature)
    @actions[feature] = :hibernate
  end
end
