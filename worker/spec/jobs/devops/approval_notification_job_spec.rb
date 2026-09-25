# frozen_string_literal: true

require 'rails_helper'

# Regression guard for IMP-7046f6e448d6: BackendApiClient#handle_response
# returns the parsed JSON body verbatim (string keys) on 2xx; it is not a
# symbol-keyed {success:, data:} envelope. Both #fetch_step_execution_details
# (`response[:data]`) and #create_approval_tokens
# (`response.dig(:data, "tokens")`) read symbol keys against the real
# string-keyed body, so the step execution was always "not found" and, even
# when it wasn't, approval tokens always came back empty (no emails sent).
RSpec.describe Devops::ApprovalNotificationJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:step_execution_id) { 'step-exec-123' }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(job).to receive(:api_client).and_return(api_client)
  end

  after { Sidekiq::Worker.clear_all }

  describe '#fetch_step_execution_details (private)' do
    it 'returns the string-keyed data payload from a real BackendApiClient body' do
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/devops/approval_tokens/#{step_execution_id}")
        .and_return('success' => true, 'data' => { 'step_name' => 'Deploy to prod' })

      result = job.send(:fetch_step_execution_details, step_execution_id)

      expect(result).to eq('step_name' => 'Deploy to prod')
    end
  end

  describe '#create_approval_tokens (private)' do
    it 'returns the string-keyed tokens array from a real BackendApiClient body' do
      recipients = ['approver@example.com']
      token_data = { 'recipient_email' => 'approver@example.com', 'raw_token' => 'tok123' }
      allow(api_client).to receive(:post)
        .with("/api/v1/internal/devops/approval_tokens/#{step_execution_id}/create_tokens", { recipients: recipients })
        .and_return('success' => true, 'data' => { 'tokens' => [token_data] })

      result = job.send(:create_approval_tokens, step_execution_id, recipients)

      expect(result).to eq([token_data])
    end
  end

  describe '#execute' do
    it 'reports the step execution as not found when the fetch legitimately fails' do
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/devops/approval_tokens/#{step_execution_id}")
        .and_raise(BackendApiClient::ApiError.new('Not found', 404))

      result = job.execute(step_execution_id, [])

      expect(result).to eq(success: false, error: 'Step execution not found')
    end

    it 'reports failed token creation when create_approval_tokens returns no tokens' do
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/devops/approval_tokens/#{step_execution_id}")
        .and_return('success' => true, 'data' => { 'step_name' => 'Deploy to prod' })
      allow(api_client).to receive(:post)
        .with("/api/v1/internal/devops/approval_tokens/#{step_execution_id}/create_tokens", { recipients: [] })
        .and_return('success' => true, 'data' => { 'tokens' => [] })

      result = job.execute(step_execution_id, [])

      expect(result).to eq(success: false, error: 'Failed to create approval tokens')
    end
  end
end
