class Cloud::Cycler::DSL::Collection
  def initialize(dsl, collection)
    @dsl = dsl
    @collection = collection
  end

  def run(&block)
    instance_eval(&block)

    if defined? @default
      unscheduled = []
      @collection.each do |instance|
        next if @dsl.catalog.has_key? instance.id
        unscheduled << instance
      end

      subcollection = Cloud::Cycler::DSL::Collection.new(@dsl, unscheduled)
      subcollection.instance_eval(@default)
    end
  end

  def with_tag(tag)
    collection = Cloud::Cycler::DSL::TaggedCollection.new(@dsl, tag, @collection.tagged(tag))
    collection.instance_eval(&block)
  end

  def filter(key, *values, &block)
    subset = @collection.filter(key, *values)
    collection = Cloud::Cycler::DSL::Collection.new(@dsl, subset)
    collection.instance_eval(&block)
  end

  def default(&block)
    @default = block
  end

  def schedule(schedule, &block)
    schedule = Cloud::Cycler::DSL::Schedule.new(schedule)
    schedule.instance_eval(&block)
    @collection.each do |instance|
      @dsl.catalog[instance.id] = schedule
    end
  end

  def ignore!
    sched = Cloud::Cycler::DSL::Schedule.empty

    @collection.each do |instance|
      @dsl.catalog[instance.id] = sched
    end
  end

  def debug(prefix = nil)
    @collection.each do |instance|
      if prefix
        @dsl.logger.debug("#{prefix} - #{instance}")
      else
        @dsl.logger.debug(instance)
      end
    end
  end
end
