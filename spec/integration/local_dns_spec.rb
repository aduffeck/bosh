require 'spec_helper'
require 'fileutils'

describe 'local DNS', type: :integration do
  with_reset_sandbox_before_each(local_dns: true)

  before do
    target_and_login
    upload_cloud_config({:cloud_config_hash => Bosh::Spec::Deployments.simple_cloud_config})
    upload_stemcell
    create_and_upload_test_release
  end

  context 'initial deployment' do
    it 'sends sync_dns action agent and updates /etc/hosts' do
      initial_deployment(1)
    end
  end

  context 'upgrade deployment from 1 to 10 instances' do
    it 'sends sync_dns action to all agents and updates all /etc/hosts' do
      manifest_deployment = initial_deployment(1)
      manifest_deployment.merge!(
          {
              'jobs' => [Bosh::Spec::Deployments.simple_job(
                  name: 'job_to_test_local_dns',
                  instances: 10)]
          })
      deploy_simple_manifest(manifest_hash: manifest_deployment)

      10.times do |i|
        check_agent_log(i)
      end

      check_agent_etc_hosts(10)
    end
  end

  context 'downgrade deployment from 10 to 5 instances' do
    it 'sends sync_dns action to all agents and updates all /etc/hosts' do
      manifest_deployment = initial_deployment(10)
      manifest_deployment.merge!(
          {
              'jobs' => [Bosh::Spec::Deployments.simple_job(
                  name: 'job_to_test_local_dns',
                  instances: 5)]
          })
      deploy_simple_manifest(manifest_hash: manifest_deployment)

      5.times do |i|
        check_agent_log(i)
      end

      check_agent_etc_hosts(5)
    end
  end

  def initial_deployment(number_of_instances)
    manifest_deployment = Bosh::Spec::Deployments.test_release_manifest
    manifest_deployment.merge!(
        {

            'jobs' => [Bosh::Spec::Deployments.simple_job(
                name: 'job_to_test_local_dns',
                instances: number_of_instances)]
        })
    deploy_simple_manifest(manifest_hash: manifest_deployment)

    number_of_instances.times { |i| check_agent_log(i) }
    check_agent_etc_hosts(number_of_instances)
    manifest_deployment
  end

  def check_agent_log(index)
    agent_id = director.vm('job_to_test_local_dns', "#{index}").agent_id
    agent_log = File.read("#{current_sandbox.agent_tmp_path}/agent.#{agent_id}.log")
    expect(agent_log).to include('"method":"sync_dns","arguments":')
  end

  def check_agent_etc_hosts(number_instance)
    number_instance.times do |i|
      agent_id = director.vm('job_to_test_local_dns', "#{i}").agent_id
      etc_hosts = File.read("#{current_sandbox.agent_tmp_path}/agent-base-dir-#{agent_id}/bosh/etc_hosts")
      expect(etc_hosts.lines.count).to be >= i
    end
  end
end
