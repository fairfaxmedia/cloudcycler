class Cloud::Cycler::DSL::TaggedCollection < Cloud::Cycler::DSL::Collection
  def initialize(dsl, tag, collection)
    @dsl = dsl
    @tag = tag
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

      subcollection = Cloud::Cycler::DSL::TaggedCollection.new(@dsl, @tag, unscheduled)
      subcollection.instance_eval(@default)
    end
  end

  def tag_value(value, &block)
    subcollection = Cloud::Cycler::DSL::TaggedCollection.new(@dsl, @tag, @collection.with_tag(@tag, value))
    subcollection.instance_eval(&block)
  end 
end
