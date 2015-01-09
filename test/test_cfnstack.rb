require 'minitest/autorun'
require 'cloud/cycler/cfnstack'
require 'cctest'
require 'pry'

class StubbedCFNStack < Cloud::Cycler::CFNStack
  attr_accessor :rebuild_safe
  attr_accessor :scaled_down

  def initialize(task, name)
    @rebuild_safe = true
    @scaled_down  = false
    super
  end

  def rebuild
    @rebuild_called = true
    super
  end

  def rebuild_safe?
    @rebuild_safe
  end

  def scaled_down?
    @scaled_down
  end

  def cf_stacks
    @cf_stacks ||= MockStackCollection.new
  end

  def s3_bucket
    @s3_bucket ||= MockS3Bucket.new(@task.bucket)
  end

  def s3_object(path)
    s3_bucket.objects[path]
  end

  def latest_rds_snapshot_of(rds_id)
    raise MissingStub.new("CFNStack#latest_rds_snapshot_of")
  end
end

class TestCFNStack < Minitest::Test
  # TODO: test scale_up/down, rds_snapshot_parameter, s3 save/load

  def test_safe_delete_stack
    test_cfn = StubbedCFNStack.new(MockTask.new(false), 'test-stack')
    stack = test_cfn.cf_stacks['test-stack']
    stack.exists = true

    test_cfn.stop(:default)
    assert !stack.delete_called
  end

  def test_unsafe_delete_stack
    test_cfn = StubbedCFNStack.new(MockTask.new(true), 'test-stack')
    stack = test_cfn.cf_stacks['test-stack']
    stack.exists = true

    test_cfn.stop(:default)
    assert stack.delete_called
  end

  def test_safe_create_deleted_stack
    test_cfn = StubbedCFNStack.new(MockTask.new(false), 'test-stack')
    test_cfn.s3_bucket.inject_template_json
    test_cfn.s3_bucket.inject_params_json
    test_cfn.s3_bucket.inject_resources_json
    stack = test_cfn.cf_stacks['test-stack']
    stack.exists = false

    test_cfn.start(:default)
    assert !test_cfn.cf_stacks.has_created?('test-stack')
  end

  def test_unsafe_create_deleted_stack
    test_cfn = StubbedCFNStack.new(MockTask.new(true), 'test-stack')
    test_cfn.s3_bucket.inject_template_json
    test_cfn.s3_bucket.inject_params_json
    test_cfn.s3_bucket.inject_resources_json
    stack = test_cfn.cf_stacks['test-stack']
    stack.exists = false

    test_cfn.start(:default)
    assert test_cfn.cf_stacks.has_created?('test-stack')
  end
end
