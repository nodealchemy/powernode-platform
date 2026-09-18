# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-3c40c97c2877: the job must call the ROUTED devops
# credential endpoints, not the unrouted /api/v1/integrations/credentials/* paths
# (the :integrations namespace only routes `instances`; credentials live under
# /api/v1/devops/integration_credentials).
RSpec.describe Integrations::CredentialRotationJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#execute with a credential_id (single rotation)' do
    it 'POSTs to the routed devops rotate endpoint' do
      expect(api_client_double).to receive(:post)
        .with('/api/v1/devops/integration_credentials/cred-123/rotate')
        .and_return({ 'success' => true })

      result = job_instance.execute('cred-123')
      expect(result[:success]).to be true
    end
  end

  describe '#execute with no id (sweep expiring credentials)' do
    it 'GETs the routed devops credentials index' do
      expect(api_client_double).to receive(:get)
        .with('/api/v1/devops/integration_credentials', { page: 1, per_page: 50 })
        .and_return({ 'success' => true, 'data' => { 'credentials' => [] } })

      result = job_instance.execute
      expect(result[:rotated]).to eq(0)
    end

    it 'reads the string-keyed BackendApiClient body to find and rotate an expiring credential' do
      expiring_credential = { 'id' => 'cred-456', 'expires_at' => 1.day.from_now.iso8601 }

      allow(api_client_double).to receive(:get)
        .with('/api/v1/devops/integration_credentials', { page: 1, per_page: 50 })
        .and_return(
          'success' => true,
          'data' => { 'credentials' => [expiring_credential], 'pagination' => { 'total_pages' => 1 } }
        )
      expect(api_client_double).to receive(:post)
        .with('/api/v1/devops/integration_credentials/cred-456/rotate')
        .and_return({ 'success' => true })

      result = job_instance.execute
      expect(result[:rotated]).to eq(1)
    end
  end

  describe '#test_instances_using_credential (private)' do
    let(:credential_id) { 'cred-456' }

    before do
      allow(job_instance).to receive(:log_info)
      allow(job_instance).to receive(:log_warn)
      allow(api_client_double).to receive(:get)
        .with('/api/v1/integrations/instances', { credential_id: credential_id, status: 'active' })
        .and_return('success' => true, 'data' => { 'instances' => [{ 'id' => 'instance-1' }] })
    end

    it 'logs a pass when the string-keyed test body reports nested success' do
      allow(api_client_double).to receive(:post)
        .with('/api/v1/integrations/instances/instance-1/test')
        .and_return('success' => true, 'data' => { 'result' => { 'success' => true } })

      expect(job_instance).to receive(:log_info).with(
        'Instance test passed after rotation', instance_id: 'instance-1', credential_id: credential_id
      )

      job_instance.send(:test_instances_using_credential, credential_id)
    end

    it 'logs a failure with the string-keyed error when the nested result reports failure' do
      allow(api_client_double).to receive(:post)
        .with('/api/v1/integrations/instances/instance-1/test')
        .and_return('success' => true, 'data' => { 'result' => { 'success' => false, 'error' => 'timeout' } })

      expect(job_instance).to receive(:log_warn).with(
        'Instance test failed after rotation', instance_id: 'instance-1', credential_id: credential_id, error: 'timeout'
      )

      job_instance.send(:test_instances_using_credential, credential_id)
    end
  end
end
