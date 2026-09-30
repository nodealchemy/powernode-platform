# frozen_string_literal: true

require 'rails_helper'

# IMP-3d275689ca7c — the REST approval reads serve two raw exception columns:
# Ai::ApprovalRequest#execution_error (core, so the queue AND the detail) and the
# deferred operation's error_message (detail only). Both are written as
# "Class: message" (Ai::ApprovalRequest#declare_execution_outcome!,
# Ai::DeferredOperation's :fail event), and an executor's message can quote the
# very params request_data redaction exists to mask. The audience is
# ai.agents.read, the floor. The MCP twin (get_approval_request,
# IMP-7f2b7b790f97) already ran both through Ai::SensitiveParams.filter_text;
# the parity block below keeps the two surfaces from drifting apart again.
RSpec.describe 'Approval read surfaces redact secrets in stored error text', type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:headers) { auth_headers_for(reader) }

  # Built at runtime from parts, and obviously fake, so no secret scanner reads
  # this file as carrying a credential.
  let(:password_value) { %w[hunter 2].join }
  let(:api_key_value) { [ 'sk', 'not-a-real-key', 'x' * 8 ].join('-') }
  let(:operation_error) do
    "RuntimeError: login failed user=ops; password=#{password_value}; attempt=2"
  end
  let(:request_error) do
    "Faraday::ClientError: rejected {\"api_key\": \"#{api_key_value}\", \"peer\": \"peer-42\"}"
  end

  before do
    Ai::InterventionPolicy.register_category!('test.error_text_action')
    Ai::InterventionPolicy.create!(
      account: account, action_category: 'test.error_text_action',
      scope: 'global', policy: 'require_approval', priority: 5, is_active: true
    )
    stub_const('ErrorTextSpecExecutor', Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
      def self.preview(_params, deferred_operation: nil) = { summary: 'error text action' }
    end)
  end

  let!(:deferred) do
    Ai::AutonomyGate.evaluate(
      action_category: 'test.error_text_action',
      executor_class: 'ErrorTextSpecExecutor',
      params: { 'principal' => { 'kind' => 'user', 'user_id' => reader.id } },
      account: account,
      requested_by: reader,
      description: 'an action whose execution failed'
    ).deferred_operation
  end
  let(:approval_request) { deferred.approval_request }

  def store_errors(execution_error:, error_message:)
    deferred.update_columns(error_message: error_message)
    approval_request.update_columns(execution_status: execution_error && 'failed', execution_error: execution_error)
  end

  def queue_row
    get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    json_response_data.find { |row| row['id'] == approval_request.id }
  end

  def detail
    get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    json_response_data
  end

  context 'when the stored error text quotes secret-named params' do
    before { store_errors(execution_error: request_error, error_message: operation_error) }

    it 'withholds the values on the queue and marks where they were' do
      row = queue_row

      expect(response.body).not_to include(password_value, api_key_value)
      expect(row['execution_error']).to include("\"api_key\": #{Ai::SensitiveParams::MASK}")
      expect(row['execution_error']).to include('peer-42')
    end

    it 'withholds the values on the detail, on both copies' do
      data = detail

      expect(response.body).not_to include(password_value, api_key_value)
      expect(data['execution_error']).to start_with('Faraday::ClientError')
      expect(data['execution_error']).to include(Ai::SensitiveParams::MASK)
      expect(data.dig('deferred_operation', 'error_message'))
        .to eq("RuntimeError: login failed user=ops; password=#{Ai::SensitiveParams::MASK}; attempt=2")
    end
  end

  context 'when the stored error text is benign' do
    let(:benign) { 'RuntimeError: upstream returned 503 for peer-42' }

    before { store_errors(execution_error: benign, error_message: benign) }

    it 'serves it unchanged on the queue and the detail' do
      expect(queue_row['execution_error']).to eq(benign)

      data = detail
      expect(data['execution_error']).to eq(benign)
      expect(data.dig('deferred_operation', 'error_message')).to eq(benign)
    end
  end

  context 'when there is no error' do
    before { store_errors(execution_error: nil, error_message: nil) }

    it 'keeps nil as nil' do
      expect(queue_row['execution_error']).to be_nil

      data = detail
      expect(data).to have_key('execution_error')
      expect(data['execution_error']).to be_nil
      expect(data.dig('deferred_operation', 'error_message')).to be_nil
    end
  end

  # The same fixture through both doors: a change to either one's redaction
  # that the other does not share fails here, not in production.
  describe 'parity with the MCP get_approval_request read' do
    before { store_errors(execution_error: request_error, error_message: operation_error) }

    it 'serves identical redacted text on REST and MCP' do
      mcp = Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        'platform.get_approval_request',
        params: { 'approval_request_id' => approval_request.id }, account: account, user: reader
      )
      rest = detail

      expect(mcp[:success]).to be(true)
      expect(rest['execution_error']).to eq(mcp[:execution_error])
      expect(rest.dig('deferred_operation', 'error_message')).to eq(mcp.dig(:deferred_operation, :error_message))
      expect(rest['execution_error']).not_to include(api_key_value)
    end
  end
end
