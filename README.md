# Cloudcycler

Cloudcycler is a system to cycle AWS cloud resources on and off on a
time-of-day basis. Internal resources such as development/testing/staging
resources may not need to be running outside office hours. Turning these off
when they are not needed helps to reduce costs.

Cloudcycler provides a `cloudcycler` command that can be run on a cron job. It
will read a single task file, or task files from a directory.

Task definitions use a ruby DSL to specify the schedule, and identify resources to be cycled.

## Currently supported:

EC2 and CloudFormation are currently supported. EC2 instances can be stopped
and started, while CloudFormation stacks can be either destroyed and rebuilt,
or have their autoscale groups set to 0 instances.

## Planned:

* Use AWS tags control schedules.
* RDS support.
* Run as a daemon?

Examples:

task 'cycle-some-resource' do
  schedule 'MTWTF-- 0800-1800'

  cloudformation\_include /-dev$/
  cloudformation\_exclude 'delicate-system-dev'
end
