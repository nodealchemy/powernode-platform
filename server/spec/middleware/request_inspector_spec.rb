# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RequestInspector do
  let(:downstream_called) { [] }
  let(:app) { ->(env) { downstream_called << env; [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:middleware) { described_class.new(app) }

  before do
    Rails.cache.clear # MemoryStore in test env — isolate per example
    # remaining_block_time reads the block TTL from Redis; stub so the block
    # response path is exercised without touching shared Redis.
    allow(Powernode::CacheRedis).to receive(:ttl).and_return(1800)
  end

  def build_env(path: '/api/v1/widgets', method: 'GET', query: nil, ip: '203.0.113.7',
                user_agent: 'Mozilla/5.0 (X11; Linux x86_64)', accept: 'application/json')
    env = Rack::MockRequest.env_for(path, method: method)
    env['QUERY_STRING'] = query if query
    env['REMOTE_ADDR'] = ip
    env['HTTP_USER_AGENT'] = user_agent
    env['HTTP_ACCEPT'] = accept if accept
    env
  end

  def call(**opts)
    middleware.call(build_env(**opts))
  end

  describe 'benign traffic' do
    it 'passes a normal request through to the app' do
      status, _headers, body = call(query: 'page=2&sort=name')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
      expect(downstream_called.size).to eq(1)
    end
  end

  describe 'blocked IPs' do
    let(:ip) { '198.51.100.42' }

    before { middleware.send(:block_ip, ip) }

    it 'returns 403 with block headers and does not reach the app' do
      status, headers, _body = call(ip: ip)
      expect(status).to eq(403)
      expect(headers['X-Request-Blocked']).to eq('true')
      expect(headers['Retry-After']).to eq('1800')
      expect(downstream_called).to be_empty
    end

    it 'still serves trusted/health paths even for a blocked IP (bypass precedes block check)' do
      status, _headers, body = call(path: '/health', ip: ip)
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    # Live incident, ops-hub 2026-08-02. The internal API is how the WORKER
    # talks to the backend (embeddings, credential decrypt) over mTLS via
    # localhost:443. A codebase index run made ~25k such calls, tripped
    # check_request_rate, and the platform IP-blocked 127.0.0.1 — i.e. itself.
    # Every embedding then failed with "Service access forbidden" while the
    # OpenAI key, egress and provider were all verifiably fine, and the 403
    # never appeared in the rails controller log because this middleware
    # rejects ahead of the controller.
    #
    # Exactly the self-brick this method's own comment already warns about for
    # node_api/worker_api — /api/v1/internal/ was simply missing from the list.
    # It is mTLS-gated (authenticate_worker_via_mtls!), so every request is
    # already bound to a NodeInstance identity and the anonymous heuristics
    # do not apply.
    it 'serves the mTLS-gated internal API even for a blocked IP' do
      status, _headers, body = call(path: '/api/v1/internal/ai/embedding_config', ip: ip)
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'still inspects ordinary API paths for a blocked IP' do
      status, _headers, _body = call(path: '/api/v1/widgets', ip: ip)
      expect(status).to eq(403)
    end
  end

  describe 'threat scoring' do
    it 'weights high-severity threat classes above the default' do
      expect(middleware.send(:threat_score, :sql_injection)).to eq(10)
      expect(middleware.send(:threat_score, :command_injection)).to eq(10)
      expect(middleware.send(:threat_score, :xss)).to eq(8)
      expect(middleware.send(:threat_score, :path_traversal)).to eq(7)
      expect(middleware.send(:threat_score, :something_unknown)).to eq(3)
    end
  end

  describe 'threat detection' do
    def inspect_query(query)
      request = Rack::Request.new(build_env(query: query))
      middleware.send(:inspect_request, request)
    end

    it 'flags a SQL-injection query string as suspicious' do
      result = inspect_query('id=1 UNION SELECT password FROM users')
      expect(result[:suspicious]).to be(true)
      expect(result[:score]).to be >= 5
      expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection)
    end

    it 'flags a path-traversal query string' do
      result = inspect_query('file=../../../../etc/passwd')
      expect(result[:threats].map { |t| t[:type] }).to include(:path_traversal)
    end

    it 'does not flag a clean query string' do
      result = inspect_query('q=hello&limit=10')
      expect(result[:suspicious]).to be(false)
      expect(result[:score]).to eq(0)
    end
  end

  # Live incident, 2026-08-07 (~19:22): a batch of MCP create_improvement calls
  # — whose payloads legitimately carry code (backtick-quoted spans, Ruby
  # assignments like "…tion_report =") — scored as command-injection/XSS,
  # crossed suspicious_request_limit, and the platform IP-blocked its own
  # improvement pipeline for an hour. The MCP channel is OAuth-authenticated at
  # the controller, so the anonymous BODY heuristics don't apply — but unlike
  # the mTLS trusted_path? prefixes it stays fully rate-checked, UA-checked,
  # size-checked, and block-ENFORCED (an already-blocked IP still 403s here).
  describe 'authenticated MCP channel body exemption' do
    let(:code_bearing_body) do
      '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"create_improvement",' \
        '"arguments":{"fix":"Change to `rescue StandardError => e` and log `Rails.logger.warn`",' \
        '"description":"@composition_report = verdict.report_entries"}}}'
    end

    def inspect_post(path:, body:, ip: '203.0.113.7')
      env = Rack::MockRequest.env_for(path, method: 'POST', input: body)
      env['REMOTE_ADDR'] = ip
      env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (X11; Linux x86_64)'
      env['HTTP_ACCEPT'] = 'application/json'
      middleware.send(:inspect_request, Rack::Request.new(env))
    end

    it 'does not score a code-bearing MCP tool payload as an attack' do
      result = inspect_post(path: '/api/v1/mcp/message', body: code_bearing_body)

      expect(result[:suspicious]).to be(false)
      expect(result[:score]).to eq(0)
    end

    # This middleware runs ahead of routing, so request.path is RAW PATH_INFO:
    # a trailing slash or format suffix is still literally present here even
    # though Rails dispatches all of these to the same controller action. An
    # exact-string exemption silently reproduces the incident for any client
    # that joins a trailing-slash base URL or appends .json.
    it 'exempts routed path variants of the MCP endpoint (trailing slash, format suffix)' do
      [ '/api/v1/mcp/message/', '/api/v1/mcp/message.json' ].each do |variant|
        result = inspect_post(path: variant, body: code_bearing_body)

        expect(result[:score]).to eq(0), "expected #{variant} to be exempt, scored #{result[:score]}"
      end
    end

    it 'does not exempt paths that merely start with the MCP endpoint string' do
      result = inspect_post(path: '/api/v1/mcp/message_extra', body: code_bearing_body)

      expect(result[:suspicious]).to be(true)
    end

    it 'still scores the same body as an attack on any other API path' do
      result = inspect_post(path: '/api/v1/widgets', body: code_bearing_body)

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:command_injection)
    end

    it 'still applies the rapid-request rate check on the MCP path' do
      allow(middleware).to receive(:get_rapid_request_count)
        .and_return(RequestInspector::THRESHOLDS[:rapid_request_threshold] + 1)

      result = inspect_post(path: '/api/v1/mcp/message', body: code_bearing_body)

      expect(result[:threats].map { |t| t[:type] }).to include(:rapid_requests)
    end

    it 'still enforces an existing IP block on the MCP path' do
      ip = '198.51.100.77'
      middleware.send(:block_ip, ip)

      env = Rack::MockRequest.env_for('/api/v1/mcp/message', method: 'POST', input: code_bearing_body)
      env['REMOTE_ADDR'] = ip
      env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (X11; Linux x86_64)'
      status, headers, _body = middleware.call(env)

      expect(status).to eq(403)
      expect(headers['X-Request-Blocked']).to eq('true')
    end
  end

  describe 'progressive blocking after repeated suspicious requests' do
    let(:ip) { '203.0.113.99' }
    let(:malicious_query) { 'id=1 UNION SELECT password FROM users' }

    it 'blocks the IP once the suspicious-request threshold is crossed, then 403s' do
      limit = RequestInspector::THRESHOLDS[:suspicious_request_limit]

      limit.times do
        status, = call(ip: ip, query: malicious_query)
        expect(status).to eq(200) # offending requests still pass until threshold blocks the IP
      end

      expect(middleware.send(:blocked?, ip)).to be(true)

      status, headers, _body = call(ip: ip, query: malicious_query)
      expect(status).to eq(403)
      expect(headers['X-Request-Blocked']).to eq('true')
    end

    it 'escalates block duration for repeat offenders' do
      first = middleware.send(:calculate_block_duration, 0)
      second = middleware.send(:calculate_block_duration, 1)
      expect(second).to be > first
      expect(middleware.send(:calculate_block_duration, 99))
        .to eq(RequestInspector::THRESHOLDS[:max_block_duration])
    end
  end
end
