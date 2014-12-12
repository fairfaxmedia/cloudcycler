class MockS3Bucket
  attr_accessor :name

  def initialize(name)
    @name = name
  end

  def objects
    @objects ||= MockS3ObjectCollection.new
  end

  def inject_params_json
    objects['parameters.json'].write("{}")
  end

  def inject_resources_json
    objects['resources.json'].write("{}")
  end

  def inject_template_json
    objects['template.json'].write("{}")
  end
end

class MockS3ObjectCollection
  def initialize
    @objects = {}
  end

  def [](name)
    @objects[name] ||= MockS3Object.new(name)
  end
end

class MockS3Object
  def initialize(name)
    @name   = name
    @exists = false
  end

  def exists?
    @content.nil?
  end

  def write(content)
    @content = content
  end

  def read
    @content
  end
end
