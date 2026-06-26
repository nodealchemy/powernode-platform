# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for cloud-instance provisioning.
#
# This job creates BILLABLE cloud instances via the backend provider API. These
# specs never call a real provider/backend: the api_client is stubbed and metric
# helpers (which would otherwise reach Redis) are stubbed out. The focus is the
# provisioning request, the success status/event/IP-association contract, and —
# most importantly — the validation guard rails that refuse to spend money.
RSpec.describe System::NodeInstanceProvisionJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:node_id) { 'node-123' }
  let(:operation_id) { 'op-456' }
  let(:operation_path) { "/api/v1/internal/system/operations/#{operation_id}" }
  let(:node_path) { "/api/v1/internal/system/nodes/#{node_id}" }
  let(:provision_path) { "#{node_path}/provision_instance" }

  let(:operation) do
    {
      'id' => operation_id,
      'options' => {
        'provider_connection_id' => 'pc-1',
        'provider_region_id' => 'r-1',
        'variety' => 'cloud'
      }
    }
  end
  let(:node) do
    {
      'id' => node_id,
      'instance_count' => 1,
      'instance_limit' => 5,
      'ssh_key' => 'ssh-rsa AAAA'
    }
  end
  let(:provision_result) do
    {
      'success' => true,
      'node_instance' => { 'id' => 'inst-1', 'name' => 'node-1-cloud', 'variety' => 'cloud' },
      'allocate_public_ip' => false
    }
  end

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)
    # Keep metrics off the Redis I/O path.
    allow(job).to receive(:track_performance_metric)
    allow(job).to receive(:increment_counter)
    allow(job).to receive(:track_error_metric)

    allow(api_client).to receive(:get).with(operation_path).and_return(operation)
    allow(api_client).to receive(:get).with(node_path).and_return(node)
    allow(api_client).to receive(:patch).and_return({})
    allow(api_client).to receive(:post).and_return({}) # operation events, etc.
    allow(api_client).to receive(:post).with(provision_path, anything).and_return(provision_result)
  end

  describe 'job configuration' do
    it 'runs on the system queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('system')
    end

    it 'retries at most once (provisioning is billable and not freely re-runnable)' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end

  describe 'successful provisioning' do
    it 'requests the cloud instance with the operation options and marks the operation complete' do
      expect(api_client).to receive(:post)
        .with(provision_path, hash_including(provider_connection_id: 'pc-1', variety: 'cloud'))
        .and_return(provision_result)
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'complete')).and_return({})

      result = job.execute(node_id, operation_id)
      expect(result[:success]).to be true
      expect(result[:instance_id]).to eq('inst-1')
    end

    it 'queues a public IP association when the node allocates a public IP' do
      provision_result['allocate_public_ip'] = true

      expect(System::NodeInstanceIpJob).to receive(:perform_async).with('inst-1', nil, 'associate')

      job.execute(node_id, operation_id)
    end

    it 'does not queue an IP association when no public IP is allocated' do
      expect(System::NodeInstanceIpJob).not_to receive(:perform_async)

      job.execute(node_id, operation_id)
    end
  end

  describe 'validation guard rails (refuse to create billable instances)' do
    it 'refuses to provision when the account instance limit is reached' do
      node['instance_count'] = 5
      node['instance_limit'] = 5

      expect(api_client).not_to receive(:post).with(provision_path, anything)
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed', error_message: a_string_matching(/instance limit/i)))
        .and_return({})

      expect(job.execute(node_id, operation_id)).to be_nil
    end

    it 'refuses to provision when the node has no SSH key' do
      node['ssh_key'] = nil

      expect(api_client).not_to receive(:post).with(provision_path, anything)
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed')).and_return({})

      expect(job.execute(node_id, operation_id)).to be_nil
    end

    it 'refuses to provision when no provider connection is specified' do
      operation['options'] = {}

      expect(api_client).not_to receive(:post).with(provision_path, anything)
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed')).and_return({})

      expect(job.execute(node_id, operation_id)).to be_nil
    end
  end

  describe 'not-found handling' do
    it 'marks the operation failed and never provisions when the node 404s' do
      allow(api_client).to receive(:get)
        .with(node_path)
        .and_raise(BackendApiClient::ApiError.new('not found', 404))

      expect(api_client).not_to receive(:post).with(provision_path, anything)
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed', error_message: 'Node not found'))
        .and_return({})

      expect(job.execute(node_id, operation_id)).to be_nil
    end
  end

  describe 'provider failure handling' do
    it 'marks the operation failed and surfaces the provider error' do
      allow(api_client).to receive(:post)
        .with(provision_path, anything)
        .and_return({ 'success' => false, 'error' => 'quota exceeded' })

      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed', error_message: 'quota exceeded'))
        .and_return({})

      result = job.execute(node_id, operation_id)
      expect(result[:success]).to be false
      expect(result[:error]).to eq('quota exceeded')
    end
  end
end
