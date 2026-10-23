# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Agent execution history list', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.agents.read' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:agent) { create(:ai_agent, account: account) }

  def items
    json_response_data['items']
  end

  it 'summarises a claude_code row from its task digest and reported model' do
    create(:ai_agent_execution, :completed, account: account, agent: agent, user: user,
           input_parameters: { 'task_digest' => 'x' * 300, 'source' => 'claude_code' },
           output_data: { 'model_used' => 'claude-opus-5' },
           tokens_used: 1200, cost_usd: 0.5,
           performance_metrics: { 'model' => 'claude-opus-5' },
           execution_context: { 'source' => 'claude_code', 'executor_kind' => 'claude_code',
                                'executor_agent_id' => 'agent-1' })

    get "/api/v1/ai/agents/#{agent.id}/executions", headers: headers, as: :json

    expect_success_response
    row = items.first
    expect(row['input_summary'].length).to eq(200)
    expect(row['output_summary']).to be_nil
    expect(row['model']).to eq('claude-opus-5')
    expect(row['source']).to eq('claude_code')
    expect(row['executor']).to eq('kind' => 'claude_code', 'agent_id' => 'agent-1')
    expect(row['tokens_used']).to eq(1200)
    expect(row['cost_usd']).to eq(0.5)
    expect(row).to include('duration_ms', 'error_message')
  end

  it 'summarises a platform row from its input and response, with no source when none was recorded' do
    create(:ai_agent_execution, :completed, account: account, agent: agent, user: user,
           input_parameters: { 'input' => 'Summarise the week' },
           output_data: { 'response' => 'R' * 250, 'metadata' => { 'model_used' => 'sonnet-x' } },
           execution_context: { 'context_type' => 'workflow' })

    get "/api/v1/ai/agents/#{agent.id}/executions", headers: headers, as: :json

    row = items.first
    expect(row['input_summary']).to eq('Summarise the week')
    expect(row['output_summary'].length).to eq(200)
    expect(row['model']).to eq('sonnet-x')
    expect(row['source']).to be_nil
    expect(row['executor']).to be_nil
  end

  it 'reads a tracked chat row from its last user message and content' do
    create(:ai_agent_execution, :completed, account: account, agent: agent, user: user,
           input_parameters: { 'messages' => [ { 'role' => 'system', 'content' => 's' }, { 'role' => 'user', 'content' => 'hello' } ] },
           output_data: { 'content' => 'hi there' })

    get "/api/v1/ai/agents/#{agent.id}/executions", headers: headers, as: :json

    expect(items.first.slice('input_summary', 'output_summary')).to eq('input_summary' => 'hello', 'output_summary' => 'hi there')
  end

  describe 'GET detail' do
    let(:secret_messages) do
      [ { 'role' => 'user',
          'content' => "api_key=sk-live-ABCDEF1234567890 mail me at jane.doe@example.com\n" \
                       "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAsecretbody\n-----END RSA PRIVATE KEY-----" } ]
    end

    it 'returns no key, PEM or email from input_parameters or output_data' do
      execution = create(:ai_agent_execution, :completed, account: account, agent: agent, user: user,
                         input_parameters: { 'messages' => secret_messages, 'message_count' => 1 },
                         output_data: { 'content' => 'reply to jane.doe@example.com with token=abc123secret', 'model_used' => 'm' })

      get "/api/v1/ai/agents/#{agent.id}/executions/#{execution.execution_id}", headers: headers, as: :json

      expect_success_response
      body = response.body
      expect(body).not_to include('sk-live-ABCDEF1234567890')
      expect(body).not_to include('MIIEowIBAAKCAQEAsecretbody')
      expect(body).not_to include('jane.doe@example.com')
      expect(body).not_to include('abc123secret')
      detail = json_response_data['execution']
      expect(detail['input_parameters']['message_count']).to eq(1)
      expect(detail['output_data']['model_used']).to eq('m')
    end
  end
end
