rundeck-fabric
==============

[![Build Status](https://travis-ci.org/balanced-cookbooks/rundeck-fabric.png?branch=master)](https://travis-ci.org/balanced-cookbooks/rundeck-fabric)

This cookbook creates a Rundeck project from a Fabric fabfile stored in git.
This allows you to use the same code for both local tasks and service-based
operations. This depends on the [Balanced version of the rundeck cookbook](https://github.com/balanced-cookbooks/rundeck).

Quick Start
-----------

Set the node attribute `['rundeck-fabric']['repository']` to a Git URI and
`include_recipe 'rundeck-fabric'`. This will create a project named "fabric"
with one job for each task in your fabfile.

### Scheduling

Currently, scheduling of tasks requires that the inner most decorated function
is decorated with string attributed named `schedule` that follows traditional
CRON expressions.

Here's [an example decorator](https://github.com/balanced-cookbooks/rundeck-fabric/blob/98dbad86590629f7c297959089faf71c9e092a16/test/cookbooks/rundeck-fabric_test/files/default/simple/fabfile.py#L5-L9)
 to help you get started.

We use a python library, [crontab](https://pypi.python.org/pypi/crontab/0.18), to parse the
cron expression and generate the appropriate schedules for tasks to execute.

Attributes
----------

* `node['rundeck-fabric']['repository']` – Git URI to clone from.
* `node['rundeck-fabric']['revision']` – Git branch or tag to use. *(default: master)*
* `node['rundeck-fabric']['version']` – Version of Fabric to install. *(default: latest)*
* `node['rundeck-fabric']['crontab_version']` – Version of Crontab to install. *(default: latest)*

Resources
---------

### rundeck_fabric_project

The `rundeck_fabric_project` resource creates a Rundeck project based on a fabfile.

```ruby
rundeck_fabric_project 'name' do
  fabric_repository 'git://...'
  fabric_revision 'release'
  fabric_version '1.8.3'
end
```

* `fabric_repository` – Git URI to clone from. *(default: node['rundeck-fabric']['repository'], required)*
* `fabric_revision` – Git branch or tag to use. *(default: node['rundeck-fabric']['revision'])*
* `fabric_version` – Version of Fabric to install. *(default: node['rundeck-fabric']['version'])*
* `crontab_version` – Version of Crontab to install. *(default: node['rundeck-fabric']['crontab_version'])*
