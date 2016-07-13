require 'spec_helper'
require 'fileutils'

describe 'local DNS', type: :integration do
  with_reset_sandbox_before_each(local_dns: true)

  let(:cloud_config) { Bosh::Spec::Deployments.simple_cloud_config }
  let(:network_name) { 'local_dns' }

  before do
    target_and_login
    cloud_config['networks'][0]['name'] = network_name
    cloud_config['compilation']['network'] = network_name
    upload_cloud_config({:cloud_config_hash => cloud_config})
    upload_stemcell
    create_and_upload_test_release
  end

  let(:ip_regexp) { /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/ }
  let(:job_name) { 'job_to_test_local_dns' }
  let(:deployment_name) { 'simple_local_dns' }
  let(:hostname_regexp) { /.*\.#{job_name}\.#{network_name}\.#{deployment_name}\.bosh/ }

  context 'small 1 instance deployment' do
    it 'sends sync_dns action agent and updates /etc/hosts' do
      initial_deployment(1)
    end
  end

  context 'upgrade deployment from 1 to 10 instances' do
    it 'sends sync_dns action to all agents and updates all /etc/hosts' do
      manifest_deployment = initial_deployment(1, 5)
      manifest_deployment['jobs'][0]['instances'] = 10
      deploy_simple_manifest(manifest_hash: manifest_deployment)

      10.times do |i|
        check_agent_log(i)
      end

      check_agent_etc_hosts(10, 10)
    end
  end

  context 'downgrade deployment from 10 to 5 instances' do
    let(:manifest_deployment) { initial_deployment(10, 5) }

    before do
      manifest_deployment['jobs'][0]['instances'] = 5
      deploy_simple_manifest(manifest_hash: manifest_deployment)

      5.times do |i|
        check_agent_log(i)
      end
    end

    it 'sends sync_dns action to all agents and updates all /etc/hosts' do
      check_agent_etc_hosts(5, 10)
    end

    it 'updates the removed vms on next scale up' do
      manifest_deployment['jobs'][0]['instances'] = 6
      deploy_simple_manifest(manifest_hash: manifest_deployment)

      5.times do |i|
        check_agent_log(i)
      end

      check_agent_etc_hosts(6, 6)
    end
  end

  def initial_deployment(number_of_instances, max_in_flight=1)
    manifest_deployment = Bosh::Spec::Deployments.test_release_manifest
    manifest_deployment.merge!(
        {
            'update' => {
                'canaries'          => 2,
                'canary_watch_time' => 4000,
                'max_in_flight'     => max_in_flight,
                'update_watch_time' => 20
            },

            'jobs' => [Bosh::Spec::Deployments.simple_job(
                name: job_name,
                instances: number_of_instances)]
        })
    manifest_deployment['name'] = deployment_name
    manifest_deployment['jobs'][0]['networks'][0]['name'] = network_name
    deploy_simple_manifest(manifest_hash: manifest_deployment)

    number_of_instances.times { |i| check_agent_log(i) }
    check_agent_etc_hosts(number_of_instances, number_of_instances)
    manifest_deployment
  end

  def check_agent_log(index)
    agent_id = director.vm('job_to_test_local_dns', "#{index}").agent_id
    agent_log = File.read("#{current_sandbox.agent_tmp_path}/agent.#{agent_id}.log")
    expect(agent_log).to include('"method":"sync_dns","arguments":')
  end

  def check_agent_etc_hosts(number_instance, expected_lines)
    number_instance.times do |i|
      agent_id = director.vm('job_to_test_local_dns', "#{i}").agent_id
      etc_hosts = File.read("#{current_sandbox.agent_tmp_path}/agent-base-dir-#{agent_id}/bosh/etc_hosts")

      expect(etc_hosts.lines.count).to eq(expected_lines)

      etc_hosts.lines.each do |line|
        words = line.strip.split(' ')
        expect(words[0]).to match(ip_regexp)
        expect(words[1]).to match(hostname_regexp)
      end
    end
  end
end
