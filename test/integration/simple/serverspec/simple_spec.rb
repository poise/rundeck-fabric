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

require 'yaml'
require 'net/http'
require 'serverspec'
include Serverspec::Helper::Exec
include Serverspec::Helper::DetectOS

ENV['RDECK_BASE'] = '/var/lib/rundeck'


class RundeckWebClient

  def initialize(username, password, options={})
    @root_uri = options['uri'] || 'http://localhost:4440'
    @username = username
    @password = password
    @connection = nil
    @cookies = nil
  end

  def login_uri
    "#{@root_uri}/user/j_security_check"
  end

  def job_uri
    "#{@root_uri}/project/fabric/job/show/%{job_id}.yaml"
  end

  def login
    uri = URI(self.login_uri)
    r = Net::HTTP.post_form(uri, j_username: @username, j_password: @password)
    @cookies = {'Cookie' => r.to_hash['set-cookie'].collect{ |ea| ea[/^.*?;/]}.join }
  end

  def fetch_job(job_id)
    uri = URI(self.job_uri % {:job_id => job_id})
    conn = Net::HTTP.new(uri.host, uri.port)
    r = conn.get(uri.path, @cookies)
    r.body
  end
end


describe command('rd-jobs -p fabric --name one --verbose --file /tmp/one --format yaml') do
  it { should return_exit_status(0) }
end

describe file('/tmp/one') do
  it { should be_a_file }
  its(:content) { should include('description: Task one.') }

  context 'fetch job from rundeck' do
    let(:deserialized) do
      job_id = YAML.load(subject.content).first['id']
      client = RundeckWebClient.new('admin', 'user')
      client.login
      YAML.load(client.fetch_job(job_id)).first['schedule']
    end

    it 'should be scheduled' do
      expected = {'time' => {'hour'=>'0', 'minute'=>'30', 'seconds'=>'0'},
                  'month'=>'*', 'year'=>'*', 'weekday'=>{'day'=>'*'}}
      deserialized.should == expected
    end
  end
end

describe command('rd-jobs -p fabric --name two --verbose --file /tmp/two --format yaml') do
  it { should return_exit_status(0) }
end

describe file('/tmp/two') do
  it { should be_a_file }
  its(:content) { should include("description: |-\n    Task\n        two.") }
  its(:content) { should include("options:\n    arg1:\n      required: true") }

  context 'fetch job from rundeck' do
    let(:deserialized) do
      job_id = YAML.load(subject.content).first['id']
      client = RundeckWebClient.new('admin', 'user')
      client.login
      YAML.load(client.fetch_job(job_id)).first['schedule']
    end

    it 'should not be scheduled' do
      deserialized.should be_nil
    end
  end
end

describe command('rd-jobs -p fabric --name three --verbose --file /tmp/three --format yaml') do
  it { should return_exit_status(0) }
end

describe file('/tmp/three') do
  it { should be_a_file }
  its(:content) { should include('description: Take three.') }
  its(:content) { should include("options:\n    c:\n      required: true\n    d:\n      value: '1'") }
  context 'fetch job from rundeck' do
    let(:deserialized) do
      job_id = YAML.load(subject.content).first['id']
      client = RundeckWebClient.new('admin', 'user')
      client.login
      YAML.load(client.fetch_job(job_id)).first['schedule']
    end

    it 'should be scheduled' do
      expected = {'time'=>{'hour'=>'0', 'minute'=>'0', 'seconds'=>'0'},
                  'month'=>'*', 'year'=>'*', 'dayofmonth'=>{'day'=>'1'}}
      deserialized.should == expected
    end
  end
end

describe file('/var/lib/rundeck/projects/fabric/etc/project.properties') do
  it { should be_a_file }
  its(:content) { should include('config.file=/var/lib/rundeck/projects/fabric/etc/resources.xml') }
end

describe file('/var/lib/rundeck/projects/fabric/etc/resources.xml') do
  it { should be_a_file }
  its(:content) { should include('name="localhost"') }
end
