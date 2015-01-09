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

## Currently supported:

EC2 and CloudFormation are currently supported. EC2 instances can be stopped
and started, while CloudFormation stacks can be either destroyed and rebuilt,
or have their autoscale groups set to 0 instances.

## Planned:

* RDS support
* Run as a daemon
* ccadm REST API

Examples:

task 'cycle-some-resource' do
  schedule 'MTWTF-- 0800-1800'

  cloudformation\_include /-dev$/
  cloudformation\_exclude /fragile-dev$/
end

$ ccadm -r ap-southeast-2 cfn mystack-dev
cfn:mystack-dev uses the default schedule
$ ccadm -r ap-southeast-2 cfn mystack-dev schedule "MTWTF-- 0600-2000"
cfn:mystack-dev now has the schedule MTWTF-- 0600-2000
$ ccadm -r ap-southeast-2 cfn mystack-dev exclude
cfn:mystack-dev will be ignored by cloudcycler
  Schedule will be MTWTF-- 0600-2000 if re-enabled
$ ccadm -r ap-southeast-2 cfn mystack-dev reset
cfn:mystack-dev will now be included in the default schedule
