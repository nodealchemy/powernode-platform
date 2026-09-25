# frozen_string_literal: true

require 'rails_helper'
require 'rack/test'

# Consumer half of the server -> worker LLM proxy contract: every /llm/* action
# hands the request's system_prompt to LlmProxyClient. Several actions extracted
# only max_tokens/effort, so the concierge's tool-path prompt and the reasoning
# services' prompts were dropped before any provider call. The producer half is
# server/spec/services/worker_llm_client_system_prompt_contract_spec.rb.
RSpec.describe JobsController, 'system_prompt on /llm/*' do
  include Rack::Test::Methods

  def app
    described_class
  end

  let(:jwt_secret) { 'test-jobs-controller-secret' }
  let(:valid_token) { JWT.encode({ 'type' => 'worker', 'sub' => 'system' }, jwt_secret, 'HS256') }
  let(:system_prompt) { 'You are the contract-test agent.' }
  let(:proxy) { instance_double(LlmProxyClient) }

  before do
    allow_any_instance_of(described_class).to receive(:jwt_secret_key).and_return(jwt_secret) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:build_llm_proxy_client).and_return(proxy) # rubocop:disable RSpec/AnyInstance
  end

  def post_llm(endpoint, body)
    header 'Authorization', "Bearer #{valid_token}"
    header 'Content-Type', 'application/json'
    post "/api/v1/llm/#{endpoint}", body.to_json
  end

  # endpoint => LlmProxyClient method it dispatches to
  {
    'complete' => :complete,
    'stream' => :complete,
    'complete_with_tools' => :complete_with_tools,
    'complete_structured' => :complete_structured,
    'execute_tool_loop' => :execute_tool_loop
  }.each do |endpoint, proxy_method|
    it "passes system_prompt through /llm/#{endpoint} to LlmProxyClient##{proxy_method}" do
      allow(proxy).to receive(proxy_method).and_return({ 'content' => 'ok' })

      post_llm(endpoint, { agent_id: 'agent-1', messages: [{ role: 'user', content: 'hi' }],
                           schema: { 'type' => 'object' }, system_prompt: system_prompt })

      expect(last_response.status).to eq(200)
      expect(proxy).to have_received(proxy_method).with(hash_including(system_prompt: system_prompt))
    end
  end
end
