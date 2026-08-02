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
