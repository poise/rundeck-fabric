#
# Author:: Noah Kantrowitz <noah@coderanger.net>
#
# Copyright 2014, Balanced, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Chef
  class Resource::RundeckFabricProject < Resource::RundeckProject
    attribute(:fabric_respository, kind_of: String, default: lazy { node['rundeck-fabric']['fabric_respository'] }, required: true)
    attribute(:fabric_revision, kind_of: String, default: lazy { node['rundeck-fabric']['fabric_revision'] })
    attribute(:fabric_version, kind_of: String, default: lazy { node['rundeck-fabric']['fabric_version'] })
    attribute(:fabric_remote_directory, kind_of: String) # For debugging, use remote_directory instead of git, set to the name of the cookbook

    def fabric_path
      ::File.join(project_path, 'fabric')
    end

    def fabric_virtualenv_path
      ::File.join(project_path, 'fabricenv')
    end
  end

  class Provider::RundeckFabricProject < Provider::RundeckProject
    include Chef::Mixin::ShellOut

    private

    def write_project_config
      r = super
      # Run these first since we need it installed to parse jobs
      notifying_block do
        install_python
        create_virtualenv
        install_fabric
      end
      clone_fabric_repository
      create_fabric_jobs
      r
    end

    def install_python
      include_recipe 'python'
    end

    def create_virtualenv
      python_virtualenv new_resource.fabric_virtualenv_path do
        owner 'root'
        group 'root'
      end
    end

    def install_fabric
      python_pip 'Fabric' do
        action :upgrade unless new_resource.fabric_version
        version new_resource.fabric_version
        virtualenv new_resource.fabric_virtualenv_path
        user 'root'
        group 'root'
      end
    end

    def clone_fabric_repository
      if new_resource.fabric_remote_directory
        remote_directory new_resource.fabric_path do
          user 'root'
          group 'root'
          source new_resource.fabric_respository
          cookbook new_resource.fabric_remote_directory
          purge true
        end
      else
        git new_resource.fabric_path do
          user 'root'
          group 'root'
          repository new_resource.fabric_respository
          revision new_resource.fabric_revision
        end
      end
    end

    FABRIC_PARSER_SCRIPT = <<-EOPY
from fabric.main import find_fabfile, load_fabfile
import inspect
import json

def visit_task(task, path):
    # Unwrap
    while hasattr(task, 'wrapped'):
        task = task.wrapped
    # Smash the closure
    if task.func_code.co_name == 'inner_decorator':
        closure = dict(zip(task.func_code.co_freevars, (c.cell_contents for c in task.func_closure)))
        task = closure.get('func', closure.get('fn', task))
    return {
        'name': task.func_name,
        'path': path,
        'doc': task.__doc__,
        'args': inspect.getargspec(task),
    }

def visit(c, path=[]):
    ret = []
    for key, value in c.iteritems():
        if isinstance(value, dict):
            ret.extend(visit(value, path + [key]))
        else:
            ret.append(visit_task(value, path))
    return ret

callables = load_fabfile(find_fabfile())[1]
print(json.dumps(visit(callables)))
EOPY

    def parse_fabric_tasks
      python = ::File.join(new_resource.fabric_virtualenv_path, 'bin', 'python')
      cmd = shell_out!([python], input: FABRIC_PARSER_SCRIPT, cwd: new_resource.fabric_path, user: 'root', group: 'root')
      Chef::JSONCompat.from_json(cmd.stdout, create_additions: false)
    end

    def create_fabric_jobs
      parse_fabric_tasks.each do |task|
        yaml = task_to_yaml(task)
        rundeck_job task['name'] do
          parent new_resource
          content yaml
        end
      end
    end

    def task_to_yaml(task)
      data = {}
      data['loglevel'] = 'INFO'
      data['description'] = task['doc']
      data['group'] = task['path'].join('/') unless task['path'].empty?
      data['sequence'] = {}
      data['sequence']['keepgoing'] = false
      data['sequence']['strategy'] = 'node-first'
      data['sequence']['commands'] = []
      data['sequence']['commands'] << {
        'exec' => "cd #{new_resource.fabric_path} && fab #{(task['path'] + [task['name']]).join('.')}",
      }
      [data].to_yaml
    end

  end
end
