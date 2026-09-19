# frozen_string_literal: true

require 'rails_helper'
require 'rack/test'

# IMP-abda86fb39be (MCP isolation Phase 0 T1) — the FIRST request-level
# spec for JobsController, the plain Rack dispatcher (worker/config.ru
# maps '/api/v1' to it directly — no Rails routing) every server ->
# worker synchronous action already goes through (/embeddings/*,
# /llm/*). Only the new /mcp/execute_stdio action is covered here;
# the pre-existing actions have zero request-level coverage today and
# adding it for them is out of this task's scope.
RSpec.describe JobsController do
  include Rack::Test::Methods

  def app
    described_class
  end

  let(:jwt_secret) { 'test-jobs-controller-secret' }
  let(:valid_token) { JWT.encode({ 'type' => 'worker', 'sub' => 'system' }, jwt_secret, 'HS256') }
  let(:server_hash) { { 'command' => 'node', 'args' => ['server.js'], 'env' => {}, 'capabilities' => {} } }
  let(:mcp_request) { { 'jsonrpc' => '2.0', 'id' => 'req-1', 'method' => 'tools/call', 'params' => {} } }

  before do
    allow_any_instance_of(described_class).to receive(:jwt_secret_key).and_return(jwt_secret) # rubocop:disable RSpec/AnyInstance
  end

  # NOTE: `body` is always passed as ONE explicit Hash literal at every
  # call site below (`post_stdio({ ... })`), never as bare trailing
  # `key: value` pairs — the latter parses as KEYWORD ARGUMENTS to
  # #post_stdio itself in Ruby 3, not as a Hash for this positional
  # parameter, and raises a confusing arity error instead of the intended
  # request body.
  def post_stdio(body, auth: valid_token)
    header 'Authorization', "Bearer #{auth}" if auth
    header 'Content-Type', 'application/json'
    post '/api/v1/mcp/execute_stdio', body.to_json
  end

  describe 'POST /api/v1/mcp/execute_stdio' do
    it 'returns 401 without a valid worker JWT' do
      post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request }, auth: nil)

      expect(last_response.status).to eq(401)
    end

    it 'returns 400 on invalid JSON' do
      header 'Authorization', "Bearer #{valid_token}"
      post '/api/v1/mcp/execute_stdio', 'not json'

      expect(last_response.status).to eq(400)
    end

    it 'returns 422 when server, mcp_request, or account_id is missing' do
      post_stdio({ account_id: 'acct-1', server: server_hash })

      expect(last_response.status).to eq(422)
    end

    it 'returns {result:} with HTTP 200 on a successful execution' do
      allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance
        .with(server_hash, mcp_request).and_return(success: true, output: { 'ok' => true })

      post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request })

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq('result' => { 'ok' => true })
    end

    # IMP-abda86fb39be review — the domain-level failure shape
    # ({error:{message:}}) is returned with HTTP 200, same as every other
    # outcome McpTransportClient#execute_stdio_request can produce
    # (security refusal, timeout, process failure) — this endpoint never
    # distinguishes them at the HTTP layer, matching what
    # Mcp::PromptService/Mcp::ResourceService#send_stdio_request used to
    # return directly when it spawned locally.
    it 'returns {error:{message:}} with HTTP 200 on a domain-level failure' do
      allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance
        .and_return(success: false, error: "Security error: 'foo' is not in the allowed list")

      post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request })

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq('error' => { 'message' => "Security error: 'foo' is not in the allowed list" })
    end

    # IMP-abda86fb39be review — the worker-side validator is MANDATORY,
    # not defense-in-depth (see Mcp::McpTransportClient's own spec for the
    # unit-level version of this same contract). This is the end-to-end
    # version: a REAL disallowed command reaching the actual HTTP action,
    # never a stub standing in for validate_stdio_server!.
    it 'end-to-end: refuses a disallowed command via the real validator and never spawns it' do
      blocked_server = server_hash.merge('command' => '/usr/bin/mcp-server')
      allow(McpSecurityService).to receive(:spawn_stdio) { raise 'spawn_stdio must not be called for a refused command' }

      post_stdio({ account_id: 'acct-1', server: blocked_server, mcp_request: mcp_request })

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['error']['message']).to match(/Security error:.*not in the allowed list/)
      expect(McpSecurityService).not_to have_received(:spawn_stdio)
    end

    # IMP-abda86fb39be review — no secrets in logs. `server['env']` can
    # carry the MCP server's own API tokens; this asserts NEITHER the
    # success/failure log lines NOR the outer unhandled-exception log line
    # ever include a secret value that was in the request body, across
    # every logger call this action can reach.
    it 'never logs the request body or env, even when an unhandled exception occurs' do
      secret_env = { 'command' => 'node', 'args' => [], 'env' => { 'API_TOKEN' => 'super-secret-value' }, 'capabilities' => {} }
      allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request).and_raise('boom') # rubocop:disable RSpec/AnyInstance
      logged_messages = []
      allow(PowernodeWorker.application.logger).to receive(:error) { |msg| logged_messages << msg }

      post_stdio({ account_id: 'acct-1', server: secret_env, mcp_request: mcp_request })

      expect(last_response.status).to eq(500)
      expect(logged_messages).not_to be_empty
      expect(logged_messages.join("\n")).not_to include('super-secret-value')
    end
  end
end
