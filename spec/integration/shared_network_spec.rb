require 'spec_helper'

describe 'shared network', type: :integration do
  with_reset_sandbox_before_each

  before do
    target_and_login
    create_and_upload_test_release
    upload_stemcell

    cloud_config_hash = Bosh::Spec::Deployments.simple_cloud_config
    # remove size from resource pools due to bug #94220432
    # where resource pools with specified size reserve extra IPs
    cloud_config_hash['resource_pools'].first.delete('size')

    cloud_config_hash['networks'].first['subnets'].first['static'] =  ['192.168.1.10', '192.168.1.11']
    upload_cloud_config(cloud_config_hash: cloud_config_hash)
  end

  let(:simple_manifest) do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['jobs'].first['instances'] = 1
    manifest_hash
  end

  let(:second_deployment_manifest) do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['jobs'].first['instances'] = 1
    manifest_hash['name'] = 'second_deployment'
    manifest_hash
  end

  def deploy_with_ip(manifest, ip, options={})
    manifest['jobs'].first['networks'].first['static_ips'] = [ip]
    options.merge!(manifest_hash: manifest)
    deploy_simple_manifest(options)
  end

  it 'deployments with shared manual network get next available IP from range' do
    deploy_simple_manifest(manifest_hash: simple_manifest)
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.2')

    deploy_simple_manifest(manifest_hash: second_deployment_manifest)
    second_deployment_vms = director.vms('second_deployment')
    expect(second_deployment_vms.size).to eq(1)
    expect(second_deployment_vms.first.ips).to eq('192.168.1.3')
  end

  it 'deployments on the same network can not use the same IP' do
    deploy_with_ip(simple_manifest, '192.168.1.10')
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.10')

    _, exit_code = deploy_with_ip(
      second_deployment_manifest,
      '192.168.1.10',
      { failure_expected: true, return_exit_code: true }
    )
    expect(exit_code).to_not eq(0)
  end

  it 'IPs used by one deployment can be used by another deployment after first deployment is deleted' do
    deploy_with_ip(simple_manifest, '192.168.1.10')
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.10')

    bosh_runner.run('delete deployment simple')

    deploy_with_ip(second_deployment_manifest, '192.168.1.10')
    second_deployment_vms = director.vms('second_deployment')
    expect(second_deployment_vms.size).to eq(1)
    expect(second_deployment_vms.first.ips).to eq('192.168.1.10')
  end

  it 'IPs released by one deployment via scaling down can be used by another deployment' do
    deploy_with_ip(simple_manifest, '192.168.1.10')
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.10')

    simple_manifest['jobs'].first['instances'] = 0
    simple_manifest['jobs'].first['networks'].first['static_ips'] = []
    deploy_simple_manifest(manifest_hash: simple_manifest)

    deploy_with_ip(second_deployment_manifest, '192.168.1.10')
    second_deployment_vms = director.vms('second_deployment')
    expect(second_deployment_vms.size).to eq(1)
    expect(second_deployment_vms.first.ips).to eq('192.168.1.10')
  end

  it 'IPs released by one deployment via changin IP can be used by another deployment' do
    deploy_with_ip(simple_manifest, '192.168.1.10')
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.10')

    deploy_with_ip(simple_manifest, '192.168.1.11')
    first_deployment_vms = director.vms
    expect(first_deployment_vms.size).to eq(1)
    expect(first_deployment_vms.first.ips).to eq('192.168.1.11')

    deploy_with_ip(second_deployment_manifest, '192.168.1.10')
    second_deployment_vms = director.vms('second_deployment')
    expect(second_deployment_vms.size).to eq(1)
    expect(second_deployment_vms.first.ips).to eq('192.168.1.10')
  end
end
