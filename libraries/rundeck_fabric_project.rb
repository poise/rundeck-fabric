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
    attribute(:fabric_rundeck_version, kind_of: String, default: lazy { node['rundeck-fabric']['fabric_rundeck_version'] })
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
      create_node_source
      # Run these first since we need it installed to parse jobs
      r = super
      install_python
      create_virtualenv
      install_fabric
      install_fabric_rundeck
      clone_fabric_repository
      delayed_create_fabric_jobs
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

    def install_fabric_rundeck
      python_pip 'fabric_rundeck' do
        action :upgrade unless new_resource.fabric_rundeck_version
        version new_resource.fabric_rundeck_version
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

    def parse_fabric_tasks
      python = ::File.join(new_resource.fabric_virtualenv_path, 'bin', 'python')
      cmd = shell_out!([python, '-m', 'fabric_rundeck'], cwd: new_resource.fabric_path, user: 'root', group: 'root')
      Chef::JSONCompat.from_json(cmd.stdout, create_additions: false)
    end

    def delayed_create_fabric_jobs
      this = self
      ruby_block 'create_fabric_jobs' do
        block do
          this.instance_exec { create_fabric_jobs }
        end
      end
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
      if task['cron'] && !task['cron'].empty?
        data['sequence'] = if task['cron'].is_a?(String)
          {'crontab' => task['cron']}
        else
          task['cron']
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
