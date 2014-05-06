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
    attribute(:fabric_repository, kind_of: String, default: lazy { node['rundeck-fabric']['repository'] }, required: true)
    attribute(:fabric_revision, kind_of: String, default: lazy { node['rundeck-fabric']['revision'] })
    attribute(:fabric_version, kind_of: String, default: lazy { node['rundeck-fabric']['version'] })
    attribute(:crontab_version, kind_of: String, default: lazy { node['rundeck-fabric']['crontab_version'] })
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

    def action_enable
      super
      notifying_block do
        create_virtualenv
        install_fabric
        install_crontab
        clone_fabric_repository
      end
      create_fabric_jobs
    end

    private

    def write_project_config
      create_node_source
      r = super
      # Run these first since we need it installed to parse jobs
      notifying_block do
        install_python
      end
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
      python_pip 'fabric' do
        action :upgrade unless new_resource.fabric_version
        version new_resource.fabric_version
        virtualenv new_resource.fabric_virtualenv_path
        user 'root'
        group 'root'
      end
    end

    def install_crontab
      python_pip 'crontab' do
        action :upgrade unless new_resource.crontab_version
        version new_resource.crontab_version
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
          source new_resource.fabric_repository
          cookbook new_resource.fabric_remote_directory
          purge true
        end
      else
        include_recipe 'git'
        git new_resource.fabric_path do
          user 'root'
          group 'root'
          repository new_resource.fabric_repository
          revision new_resource.fabric_revision
        end
      end
    end

    FABRIC_PARSER_SCRIPT = <<-EOPY
import inspect
import json

from crontab import CronTab
from fabric.main import find_fabfile, load_fabfile

def explode_cron(schedule_string):

    if not schedule_string:
        return {}

    schedule = {
        'time': {
            'seconds': '0',
            'minute': '0',
            'hour': '0',
        },
        'month': '*',
        'dayofmonth': {
            'day': '1',
        },
        'weekday': {
            'day': '*'
        },
        'year': '*'
    }

    cron = CronTab(schedule_string)
    if not cron.matchers.minute.any:
        schedule['time']['minute'] = cron.matchers.minute.input

    if not cron.matchers.hour.any:
        schedule['time']['hour'] = cron.matchers.hour.input

    if not cron.matchers.day.any:
        schedule['dayofmonth']['day'] = cron.matchers.day.input

    if not cron.matchers.month.any:
        schedule['month'] = cron.matchers.month.input

    if not cron.matchers.weekday.any:
        schedule['weekday']['day'] = cron.matchers.weekday.input

    if not cron.matchers.year.any:
        schedule['year'] = cron.matchers.year.input

    #  http://wiki.gentoo.org/wiki/Cron
    if all([cron.matchers.day.any, cron.matchers.weekday.any]):
        # if both are specified, it means every day, so remove
        # dayofmonth (since Rundeck gets confused)
        del schedule['dayofmonth']
    elif not cron.matchers.day.any and cron.matchers.weekday.any:
        del schedule['weekday']
    elif cron.matchers.day.any and not cron.matchers.weekday.any:
        del schedule['dayofmonth']

    return schedule

def visit_task(task, path):
    # Unwrap
    while hasattr(task, 'wrapped'):
        task = task.wrapped
    # Smash the closure
    if task.func_code.co_name == 'inner_decorator':
        closure = dict(zip(task.func_code.co_freevars, (c.cell_contents for c in task.func_closure)))
        task = closure.get('func', closure.get('fn', task))
    args = inspect.getargspec(task)
    return {
        'name': task.func_name,
        'path': path,
        'doc': task.__doc__,
        'schedule': explode_cron(getattr(task, 'schedule', None)),
        'argspec': {
          'args': args.args,
          'varargs': args.varargs,
          'keywords': args.keywords,
          'defaults': args.defaults,
        },
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
      argspec = task['argspec']
      data = {}
      data['schedule'] = task['schedule']
      data['loglevel'] = 'INFO'
      data['description'] = task['doc']
      data['group'] = task['path'].join('/') unless task['path'].empty?
      data['sequence'] = {}
      data['sequence']['keepgoing'] = false
      data['sequence']['strategy'] = 'node-first'
      data['sequence']['commands'] = []
      data['sequence']['commands'] << {}
      cmd = "cd #{new_resource.fabric_path} && "
      cmd << "#{::File.join(new_resource.fabric_virtualenv_path, 'bin', 'fab')} #{(task['path'] + [task['name']]).join('.')}"
      unless argspec['args'].empty?
        cmd << ":#{argspec['args'].map{|arg| "#{arg}=${option.#{arg}}"}.join(',')}"
      end
      data['sequence']['commands'][0]['exec'] = cmd
      data['options'] = {}
      # The defaults array starts from the end of the args list
      arg_defaults = if argspec['defaults']
        Hash[argspec['args'][-1*argspec['defaults'].length..-1].zip(argspec['defaults'])]
      else
        {}
      end
      argspec['args'].each do |arg|
        data['options'][arg] = {}
        if arg_defaults.include?(arg)
          # It has a default value
          data['options'][arg]['value'] = arg_defaults[arg].to_s
        else
          data['options'][arg]['required'] = true
        end
      end
      [data].to_yaml
    end

    def create_node_source
      rundeck_fabric_node_source new_resource.name do
        parent new_resource
      end
    end

  end
end
