rundeck-fabric
=============

[![Build Status](https://travis-ci.org/balanced-cookbooks/rundeck-fabric.png?branch=master)](https://travis-ci.org/balanced-cookbooks/rundeck-fabric)

Quick Start
-----------


Attributes
----------

* `node['rundeck-fabric']['option']` – Description of option. *(default: something)*

Resources
---------

### rundeck_fabric

The `rundeck_fabric` resource defines a something.

```ruby
rundeck_fabric 'name' do
  option 'a'
end
```

* `option` – Description of option. *(default: node['rundeck-fabric']['option'])*
