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
  let(:server_hash) { { 'command' => 'node', 'args' => [ 'server.js' ], 'env' => {}, 'capabilities' => {}, 'account_id' => 'acct-1' } }
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
  #
  # IMP-f010c9fc7051: every request carries a valid `timeout_seconds` (the
  # server always sends one) unless a test passes its own — `:omit` drops
  # the key entirely, for the missing-field case.
  def post_stdio(body, auth: valid_token, timeout_seconds: 15)
    body = body.merge(timeout_seconds: timeout_seconds) unless timeout_seconds == :omit
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
        .with(server_hash, mcp_request, timeout: 15).and_return(success: true, output: { 'ok' => true })

      post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request })

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq('result' => { 'ok' => true })
    end

    # IMP-bd260c0b4c00 — the sandbox identity is keyed on the MCP server's
    # OWNING account, exactly as on the async path. The server payload
    # carries it; the request's account_id is the caller's.
    it "keys the spawn on the server payload's owning account" do
      success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
      expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, account_id:, **_kwargs|
        expect(account_id).to eq('acct-1')
        [ '{"jsonrpc":"2.0","id":"req-1","result":{"ok":true}}', '', success_status ]
      end

      post_stdio({ account_id: 'ACCT-1 ', server: server_hash.merge('account_id' => 'acct-1'), mcp_request: mcp_request })

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq('result' => { 'ok' => true })
    end

    # No fallback to the caller's account: a payload without the server
    # owner fails closed, spawning nothing.
    [ nil, '', '  ' ].each do |blank|
      it "refuses with 422, spawning nothing, when the server payload's account_id is #{blank.inspect}" do
        expect(McpSecurityService).not_to receive(:spawn_stdio)
        expect_any_instance_of(Mcp::McpTransportClient).not_to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance

        post_stdio({ account_id: 'acct-1', server: server_hash.merge('account_id' => blank), mcp_request: mcp_request })

        expect(last_response.status).to eq(422)
        expect(JSON.parse(last_response.body).to_s).to match(/owner/i)
      end
    end

    it 'refuses with 422 when the server payload has no account_id key at all' do
      expect(McpSecurityService).not_to receive(:spawn_stdio)

      post_stdio({ account_id: 'acct-1', server: server_hash.except('account_id'), mcp_request: mcp_request })

      expect(last_response.status).to eq(422)
    end

    it 'refuses with 422, spawning nothing, when the request account and the server owner disagree' do
      expect(McpSecurityService).not_to receive(:spawn_stdio)
      expect_any_instance_of(Mcp::McpTransportClient).not_to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance

      post_stdio({ account_id: 'acct-1', server: server_hash.merge('account_id' => 'someone-else'), mcp_request: mcp_request })

      expect(last_response.status).to eq(422)
      expect(JSON.parse(last_response.body).to_s).to match(/account/i)
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
      secret_env = { 'command' => 'node', 'args' => [], 'env' => { 'API_TOKEN' => 'super-secret-value' }, 'capabilities' => {}, 'account_id' => 'acct-1' }
      allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request).and_raise('boom') # rubocop:disable RSpec/AnyInstance
      logged_messages = []
      allow(PowernodeWorker.application.logger).to receive(:error) { |msg| logged_messages << msg }

      post_stdio({ account_id: 'acct-1', server: secret_env, mcp_request: mcp_request })

      expect(last_response.status).to eq(500)
      expect(logged_messages).not_to be_empty
      expect(logged_messages.join("\n")).not_to include('super-secret-value')
    end

    # IMP-f010c9fc7051 — the synchronous deadline arrives per request from
    # the server's SiteSetting. It is request-body input under a shared
    # worker JWT, so it is validated here and REJECTED (not clamped) when
    # it is anything but a positive Integer within MAX_STDIO_TIMEOUT_SECONDS:
    # a huge value must never hold a worker slot, and a malformed one means
    # the caller is broken, which a silent clamp would hide.
    describe 'timeout_seconds' do
      it 'hands an in-range timeout to spawn_stdio as its deadline' do
        success_status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(McpSecurityService).to receive(:spawn_stdio) do |_command, _env, _args, stdin_data:, timeout:, **_kwargs|
          expect(timeout).to eq(7)
          [ '{"jsonrpc":"2.0","id":"req-1","result":{"ok":true}}', '', success_status ]
        end

        post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request }, timeout_seconds: 7)

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)).to eq('result' => { 'ok' => true })
      end

      it 'accepts exactly MAX_STDIO_TIMEOUT_SECONDS' do
        max = McpSecurityService::MAX_STDIO_TIMEOUT_SECONDS
        allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance
          .with(server_hash, mcp_request, timeout: max).and_return(success: true, output: {})

        post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request }, timeout_seconds: max)

        expect(last_response.status).to eq(200)
      end

      [ :omit, nil, '15', 15.0, 15.5, 0, -1, true ].each do |bad|
        it "refuses with 422, spawning nothing, when timeout_seconds is #{bad == :omit ? 'missing' : bad.inspect}" do
          expect(McpSecurityService).not_to receive(:spawn_stdio)
          expect_any_instance_of(Mcp::McpTransportClient).not_to receive(:execute_stdio_request) # rubocop:disable RSpec/AnyInstance

          post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request }, timeout_seconds: bad)

          expect(last_response.status).to eq(422)
          expect(JSON.parse(last_response.body).to_s).to match(/timeout_seconds/)
        end
      end

      it 'refuses with 422, spawning nothing, when timeout_seconds is above MAX_STDIO_TIMEOUT_SECONDS' do
        expect(McpSecurityService).not_to receive(:spawn_stdio)

        post_stdio({ account_id: 'acct-1', server: server_hash, mcp_request: mcp_request },
                   timeout_seconds: McpSecurityService::MAX_STDIO_TIMEOUT_SECONDS + 1)

        expect(last_response.status).to eq(422)
        expect(JSON.parse(last_response.body).to_s).to match(/timeout_seconds/)
      end
    end

    # IMP-ecc0e18c0455 — every synchronous stdio MCP call holds a worker-web
    # Puma thread for its whole deadline, on a pool shared with the LLM
    # proxy, streaming and embeddings. A process-wide cap refuses the call
    # that would exceed it, at once (never queueing a thread behind a
    # slot), and a slot is given back on EVERY exit path.
    describe 'concurrency cap' do
      let(:limiter) { Mcp::StdioConcurrencyLimiter.new(limit: 1) }
      let(:valid_body) { { account_id: 'acct-1', server: server_hash, mcp_request: mcp_request } }
      let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
      let(:ok_stdout) { '{"jsonrpc":"2.0","id":"req-1","result":{"ok":true}}' }

      before { described_class.stdio_limiter = limiter }
      after { described_class.stdio_limiter = nil }

      # Rack::Test's `post`/`last_response` belong to one session, so a
      # request made from a second thread goes through its own MockRequest.
      def raw_post_stdio(body = valid_body)
        Rack::MockRequest.new(described_class).post(
          '/api/v1/mcp/execute_stdio',
          'CONTENT_TYPE' => 'application/json',
          'HTTP_AUTHORIZATION' => "Bearer #{valid_token}",
          input: body.merge(timeout_seconds: 15).to_json
        )
      end

      # A request made while another is held. Run on its own thread and
      # bounded, so a request that is wrongly admitted (and so parks inside
      # the held spawn) fails the example instead of hanging the suite.
      def post_while_held(body = valid_body)
        request = Thread.new { raw_post_stdio(body) }
        raise 'the request did not return while the slot was held' unless request.join(30)

        request.value
      end

      # Holds one execution open inside spawn_stdio until the block is done,
      # then returns that held request's own response. `entered` is the
      # latch: popping it proves the first request is past the cap and
      # inside the spawn. No sleeps anywhere; the pop's timeout only turns
      # a request that never reached the spawn into a failure, not a hang.
      def hold_one_execution
        entered = Thread::Queue.new
        gate = Thread::Queue.new
        allow(McpSecurityService).to receive(:spawn_stdio) do
          entered << :in
          gate.pop
          [ ok_stdout, '', success_status ]
        end
        holder = Thread.new { raw_post_stdio }
        raise 'the held request never reached spawn_stdio' unless entered.pop(timeout: 30)

        yield
        gate.close
        holder.value
      ensure
        # Closing (not pushing) wakes EVERY thread parked on the gate, so a
        # request that was wrongly admitted cannot strand the example.
        gate.close
        holder&.join(30)
      end

      it 'refuses the call over the cap at once with 503 and {error:{message:}}, while the first is still running' do
        held_response = hold_one_execution do
          refused = post_while_held

          expect(refused.status).to eq(503)
          expect(JSON.parse(refused.body))
            .to eq('error' => { 'message' => 'MCP stdio capacity exhausted', 'code' => 'mcp_stdio_capacity_exhausted' })
          expect(McpSecurityService).to have_received(:spawn_stdio).once
          expect(limiter.in_flight).to eq(1)
        end

        # The held call was never disturbed, and its slot came back.
        expect(held_response.status).to eq(200)
        expect(JSON.parse(held_response.body)).to eq('result' => { 'ok' => true })
        expect(limiter.in_flight).to eq(0)
      end

      it 'admits up to the cap concurrently, not just one at a time' do
        described_class.stdio_limiter = Mcp::StdioConcurrencyLimiter.new(limit: 2)
        entered = Thread::Queue.new
        gate = Thread::Queue.new
        allow(McpSecurityService).to receive(:spawn_stdio) do
          entered << :in
          gate.pop
          [ ok_stdout, '', success_status ]
        end

        holders = Array.new(2) { Thread.new { raw_post_stdio } }
        begin
          2.times { raise 'a held request never reached spawn_stdio' unless entered.pop(timeout: 30) }

          expect(post_while_held.status).to eq(503)
        ensure
          gate.close
        end
        expect(holders.map { |t| t.value.status }).to eq([ 200, 200 ])
      end

      it 'names the saturation in a warning, without logging the request body or env' do
        logged = []
        allow(PowernodeWorker.application.logger).to receive(:warn) { |msg| logged << msg }
        secret_server = server_hash.merge('env' => { 'API_TOKEN' => 'super-secret-value' })

        refused = nil
        hold_one_execution { refused = post_while_held(valid_body.merge(server: secret_server)) }

        expect(refused.status).to eq(503)
        expect(logged.size).to eq(1)
        expect(logged.first).to match(/capacity exhausted/i).and match(/cap 1\b/).and match(/1 refused/)
        expect(logged.first).not_to include('super-secret-value')
        expect(logged.first).not_to include('acct-1')
      end

      # A request the earlier checks refuse gets its own answer even when
      # every slot is taken, and never takes one.
      describe 'ordering against the existing checks' do
        before { limiter.try_acquire }

        it 'still answers 401 before the cap' do
          post_stdio(valid_body, auth: nil)

          expect(last_response.status).to eq(401)
        end

        it 'still answers 400 for invalid JSON before the cap' do
          header 'Authorization', "Bearer #{valid_token}"
          post '/api/v1/mcp/execute_stdio', 'not json'

          expect(last_response.status).to eq(400)
        end

        it 'still answers 422 for a missing field, an owner mismatch and a bad timeout before the cap' do
          post_stdio({ account_id: 'acct-1', server: server_hash })
          expect(last_response.status).to eq(422)

          post_stdio(valid_body.merge(server: server_hash.merge('account_id' => 'someone-else')))
          expect(last_response.status).to eq(422)

          post_stdio(valid_body, timeout_seconds: 0)
          expect(last_response.status).to eq(422)

          expect(limiter.rejected_total).to eq(0)
        end

        it 'refuses a fully valid request once the checks pass' do
          expect(McpSecurityService).not_to receive(:spawn_stdio)

          post_stdio(valid_body)

          expect(last_response.status).to eq(503)
          expect(limiter.rejected_total).to eq(1)
        end
      end

      # The production wiring: with no limiter injected, the controller uses
      # the process-wide Mcp::StdioConcurrencyLimiter.instance.
      it 'enforces the process-wide limiter when none is injected' do
        described_class.stdio_limiter = nil
        Mcp::StdioConcurrencyLimiter.reset_instance!
        allow(Mcp::StdioConcurrencyLimiter).to receive(:resolve_limit).and_return(1)
        expect(McpSecurityService).not_to receive(:spawn_stdio)
        Mcp::StdioConcurrencyLimiter.instance.try_acquire

        post_stdio(valid_body)

        expect(last_response.status).to eq(503)
      ensure
        Mcp::StdioConcurrencyLimiter.reset_instance!
      end

      it 'does not take a slot for a request refused by the earlier checks' do
        expect(McpSecurityService).not_to receive(:spawn_stdio)

        # Unauthenticated first: Rack::Test keeps a header once it is set.
        statuses = [
          post_stdio(valid_body, auth: nil),
          post_stdio({ account_id: 'acct-1', server: server_hash }),
          post_stdio(valid_body, timeout_seconds: 0)
        ].map(&:status)

        expect(statuses).to eq([ 401, 422, 422 ])
        expect(limiter.in_flight).to eq(0)
        expect(limiter.rejected_total).to eq(0)
      end

      # Each example fills the single slot, leaves by one exit path, and
      # then shows the slot is back by having a FOLLOWING request admitted
      # (it reaches spawn_stdio and answers 200). With cap 1, a leaked slot
      # makes that following request a 503.
      describe 'slot release' do
        def expect_next_request_admitted
          allow(McpSecurityService).to receive(:spawn_stdio).and_return([ ok_stdout, '', success_status ])

          post_stdio(valid_body)

          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body)).to eq('result' => { 'ok' => true })
          expect(limiter.in_flight).to eq(0)
        end

        it 'frees the slot after a normal return' do
          allow(McpSecurityService).to receive(:spawn_stdio).and_return([ ok_stdout, '', success_status ])
          post_stdio(valid_body)
          expect(last_response.status).to eq(200)

          expect_next_request_admitted
        end

        it 'frees the slot after a domain-level failure' do
          failed_status = instance_double(Process::Status, success?: false, exitstatus: 3)
          allow(McpSecurityService).to receive(:spawn_stdio).and_return([ '', 'nope', failed_status ])
          post_stdio(valid_body)
          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body)['error']['message']).to match(/exited with code 3/)

          expect_next_request_admitted
        end

        it 'frees the slot after the child times out' do
          allow(McpSecurityService).to receive(:spawn_stdio)
            .and_raise(McpSecurityService::StdioTimeoutError, "stdio MCP server 'node' exceeded 15s and was killed")
          post_stdio(valid_body)
          expect(last_response.status).to eq(200)
          expect(JSON.parse(last_response.body)['error']['message']).to match(/exceeded 15s/)

          expect_next_request_admitted
        end

        it 'frees the slot after an unhandled StandardError (the 500 path)' do
          calls = 0
          allow_any_instance_of(Mcp::McpTransportClient).to receive(:execute_stdio_request) do # rubocop:disable RSpec/AnyInstance
            calls += 1
            raise 'boom' if calls == 1

            { success: true, output: { 'ok' => true } }
          end
          post_stdio(valid_body)
          expect(last_response.status).to eq(500)

          expect_next_request_admitted
        end

        # Not a StandardError, so no `rescue` in this controller sees it:
        # only an `ensure` gives the slot back. This is the shape of a
        # request thread being torn down mid-call.
        it 'frees the slot when a non-StandardError unwinds the request' do
          teardown = Class.new(Exception) # rubocop:disable Lint/InheritException
          allow(McpSecurityService).to receive(:spawn_stdio).and_raise(teardown)

          expect { post_stdio(valid_body) }.to raise_error(teardown)

          expect_next_request_admitted
        end
      end
    end
  end
end
