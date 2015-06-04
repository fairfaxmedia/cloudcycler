# Cloudcycler

Cloudcycler is a system to cycle AWS cloud resources on and off on a
time-of-day basis. Internal resources such as development/testing/staging
resources may not need to be running outside office hours. Turning these off
when they are not needed helps to reduce costs.

Cloudcycler provides a `cloudcycler` command that can be run on a cron job. It
will read a single task file, or task files from a directory.

Task definitions use a ruby DSL to specify the schedule, and identify resources to be cycled.

A `ccadm` utility is provided to control per-resource settings, which overrides
task level settings. This way, resources can be rescheduled or excluded without
having to manage and/or deploy task files.

## Currently supported

EC2 instances can be stopped and started.

Autoscaling groups have their processes suspended, and the underlying instances
either terminated (default) or stopped.

CloudFormation stacks can be deleted and rebuilt with the same template and
parameters. Alternatively, the list of stack resources will be scanned, and the
resources will be stopped/started individually.

## Planned

* Run as a daemon (will allow more fine-grained scheduling)
* ccadm REST API
* Better reporting

## Install

Add the following to a Gemfile:

```ruby
sources 'https://rubygems.org'

gem 'cloudcycler', git: 'https://github.com/fairfaxmedia/cloudcycler.git'
```

And then run `bundle install`

### Create a DynamoDB table

A DynamoDB is used to store schedules created by the `ccadm` utility. These 
schedules are read by the `cloudcycler` utility.

Create a DynamoDB table called `cloudcycler` with a Hash Key called `name`.

### Create an S3 bucket

An S3 bucket is needed to store configuration about CloudFormation stacks. The
configuration is used when restoring a CloudFormation stack that was previously
scaled down.

The bucket can have any name but must be supplied to the `cloudcycler` utility.

## Basic usage

For more information on how to use the `ccadm` utility, type `ccadm --help` in your console.

To check the schedule of a CloudFormation stack:

```
$ ccadm -r ap-southeast-2 cfn mystack-dev
cfn:mystack-dev uses the default schedule
```

To change the schedule of a stack:

```
$ ccadm -r ap-southeast-2 cfn mystack-dev schedule "MTWTF-- 0600-2000"
cfn:mystack-dev now has the schedule MTWTF-- 0600-2000
```

To exclude certain stacks from a schedule:

```
$ ccadm -r ap-southeast-2 cfn mystack-dev exclude
cfn:mystack-dev will be ignored by cloudcycler
  Schedule will be MTWTF-- 0600-2000 if re-enabled
```

To reset a stack to the default schedule (do not cycle):

```
$ ccadm -r ap-southeast-2 cfn mystack-dev reset
cfn:mystack-dev will now be included in the default schedule
```

For more information on how to use the `cloudcycler` utility, type `cloudcycler --help` in your console.

To use the `cloudcycler` utility:

```
$ cloudcycler -r ap-southeast-2
```

### Cloudcycler config file

The `cloudcycler` utility can read configuration from a YAML file.

* `region` - default AWS region
* `log-file` - file to log to
* `bucket-name` - default S3 bucket
* `bucket-prefix` - prefix (folder) for S3 objects
* `bucket-region` - region for S3 bucket
* `task-file` - task file
* `take-directory` - task directory

### Schedule syntax

e.g. Schedule to be on between 08:00 and 18:00 Monday to Friday

```
MTWTF-- 0800-1800
```

* `MTWTFSS` will toggle the day on
* `-` or any other charcter will toggle the day off
* Start and stop times are in 24-hour format
* Dates/times are based on your local timezone

## Using the DSL

```ruby
task 'cycle-some-resource' do
  schedule 'MTWTF-- 0800-1800'

  cloudformation_include /-dev$/
  cloudformation_exclude /fragile-dev$/
end
```

Use the `cloudcycler` utility to run your task files.

```
$ cloudcycler -r ap-southeast-2 -b bucket-name -f task_file.rb
```

### Global options

The following options can be declared directly inside a task file.

#### default_bucket

Sets the default S3 bucket to store configuration files, etc.

This can also be defined in `task` blocks.

#### default_bucket_prefix

Default prefix (i.e. folder) to prepend to S3 object names.

#### default_bucket_region

Default region for S3 buckets, if different from the region being cycled.

#### dryrun!

Sets the application to dry-run mode.

#### log_to

Changes the logger. May be any type accepted by `Logger::new` (i.e. a
filename, `String`, or `IO`).

#### task

See [Tasks](#tasks) below.

### Tasks

Use a `task` block to define a task.

#### region

Overwrite the default region provided outside of the `task` block.

#### bucket

Overwrite the default S3 bucket provided outside of the `task` block.

#### bucket_prefix

Overwrite the default S3 bucket prefix provided outside of the `task` block.

#### bucket_region

Overwrite the default S3 bucket prefix provided outside of the `task` block.

#### ec2_include

An `Array` of EC2 instances by instance ID to be cycled.

#### ec2_exclude

Blacklist EC2 instances to be excluded from pattern matching.

#### cloudformation_include

An `Array` of CloudFormation stacks by stack name to be cycled.

#### cloudformation_exclude

Blacklist Cloudformation stacks to be excluded from pattern matching.

#### cfn_rds_snapshot_parameter

#### schedule

See [Schedule syntax](#schedule-syntax) for usage.

#### ec2_action

_(Currently Cloudcycler only supports stop/start action right now)._

#### cfn_action

Available options are:

* `:delete` - saves data about the stack and then deletes it. Fails down to `:scale_down` if certain checks fail
* `:scale_down` - suspends auto-scaling groups and stops EC2 instances within the stack

The `:delete` action will check the following conditions are met before deleting a stack:

* Multiple DB instances (RDS snapshot not supported for multiple DB instances)
* `rds_snapshot_parameter` must be defined if DB instances are present
* CloudFormation template must accept the value supplied for `rds_snapshot_parameter`

#### autoscaling_action

_(Current Cloudcycler only supports suspend/resume action right now)._

