# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for provider-volume lifecycle management.
#
# This job drives data-availability-critical operations (attach/detach/recover)
# against provider storage. These specs never touch a real provider or backend:
# the api_client is stubbed, and metric helpers (which would otherwise reach
# Redis) are stubbed out. The focus is command-dispatch routing, the attach/
# detach guard rails, and the operation status contract.
RSpec.describe System::VolumeManagementJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:volume_id) { 'vol-123' }
  let(:operation_id) { 'op-456' }
  let(:operation_path) { "/api/v1/internal/system/operations/#{operation_id}" }
  let(:volume_path) { "/api/v1/internal/system/provider_volumes/#{volume_id}" }

  let(:volume) do
    {
      'id' => volume_id,
      'name' => 'data-vol',
      'status' => 'available',
      'node_instance_id' => 'inst-789',
      'active_instance_id' => 'inst-789'
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

    allow(api_client).to receive(:get).with(volume_path).and_return(volume)
    allow(api_client).to receive(:patch).and_return({})
    allow(api_client).to receive(:post).and_return({ 'success' => true })
  end

  describe 'job configuration' do
    it 'runs on the system queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('system')
    end

    it 'retries at most twice' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end
  end

  describe 'command dispatch routing' do
    it "routes 'attach' to the volume attach endpoint" do
      expect(api_client).to receive(:post).with("#{volume_path}/attach").and_return({ 'success' => true })
      job.execute(volume_id, operation_id, 'attach')
    end

    it "routes 'detach' to the volume detach endpoint" do
      volume['status'] = 'attached'
      expect(api_client).to receive(:post).with("#{volume_path}/detach").and_return({ 'success' => true })
      job.execute(volume_id, operation_id, 'detach')
    end

    it "routes 'provision' to the volume provision endpoint" do
      expect(api_client).to receive(:post).with("#{volume_path}/provision").and_return({ 'success' => true })
      job.execute(volume_id, operation_id, 'provision')
    end

    it "routes 'recover' to the volume recover endpoint" do
      expect(api_client).to receive(:post).with("#{volume_path}/recover").and_return({ 'success' => true })
      job.execute(volume_id, operation_id, 'recover')
    end

    it "routes 'check' to the volume check endpoint" do
      expect(api_client).to receive(:post).with("#{volume_path}/check").and_return({ 'success' => true, 'actions' => [] })
      job.execute(volume_id, operation_id, 'check')
    end
  end

  describe 'guard rails' do
    it 'refuses to attach a volume that is not available and never calls the provider' do
      volume['status'] = 'in_use'

      expect(api_client).not_to receive(:post).with("#{volume_path}/attach")
      # handle_failure marks the operation failed.
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed')).and_return({})

      result = job.execute(volume_id, operation_id, 'attach')
      expect(result[:success]).to be false
    end

    it 'refuses to detach a volume that is not attached and never calls the provider' do
      volume['status'] = 'available'

      expect(api_client).not_to receive(:post).with("#{volume_path}/detach")

      result = job.execute(volume_id, operation_id, 'detach')
      expect(result[:success]).to be false
    end

    it 'raises on an invalid command and marks the operation failed' do
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed')).and_return({})

      expect { job.execute(volume_id, operation_id, 'frobnicate') }.to raise_error(ArgumentError, /Invalid command/)
    end
  end

  describe 'not-found handling' do
    it 'returns a failure result when the volume 404s, without dispatching any action' do
      allow(api_client).to receive(:get)
        .with(volume_path)
        .and_raise(BackendApiClient::ApiError.new('not found', 404))

      expect(api_client).not_to receive(:post)

      result = job.execute(volume_id, operation_id, 'attach')
      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/i)
    end
  end

  describe 'status contract' do
    it 'marks the operation running then complete on a successful attach' do
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'running')).ordered.and_return({})
      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'complete')).ordered.and_return({})

      job.execute(volume_id, operation_id, 'attach')
    end

    it 'marks the operation failed when the provider rejects the operation' do
      allow(api_client).to receive(:post)
        .with("#{volume_path}/recover")
        .and_return({ 'success' => false, 'error' => 'provider unavailable' })

      expect(api_client).to receive(:patch)
        .with(operation_path, hash_including(status: 'failed')).and_return({})

      result = job.execute(volume_id, operation_id, 'recover')
      expect(result[:success]).to be false
    end
  end
end
