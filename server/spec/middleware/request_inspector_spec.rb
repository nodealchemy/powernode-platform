# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RequestInspector do
  let(:downstream_called) { [] }
  let(:app) { ->(env) { downstream_called << env; [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:middleware) { described_class.new(app) }

  # DDoS state lives in Redis now (Security::IpBlockStore), NOT Rails.cache —
  # the hub pins CACHE_STORE=memory_store, which made blocks per puma worker and
  # lost them on restart. Clear only this store's own keys: the redis test
  # database is shared by every rspec process on the box, so a FLUSHDB here
  # would take out a concurrent run.
  before do
    Security::IpBlockStore.with do |redis|
      redis.scan_each(match: "#{Security::IpBlockStore::PREFIX}:*") { |key| redis.del(key) }
    end
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
      expect(downstream_called).to be_empty
    end

    # Retry-After used to be the hardcoded 3600 on every deployment whose
    # Rails.cache was not a Redis store — the TTL read resolved Redis OFF
    # Rails.cache and got nil. It is now the block's real remaining time.
    it 'reports the block’s ACTUAL remaining time in Retry-After' do
      _status, headers, _body = call(ip: ip)

      expect(headers['Retry-After'].to_i)
        .to be_between(described_class.threshold(:block_duration_seconds) - 60,
                       described_class.threshold(:block_duration_seconds))
    end

    # THE CROSS-PROCESS PROPERTY. A block written by one puma worker used to be
    # invisible to every other worker, so a blocked attacker still reached the
    # app on all but one — with Rails.cache as MemoryStore the blocklist was
    # per PROCESS. A second middleware instance stands in for the sibling
    # worker: it shares no Ruby state with the one that issued the block.
    it 'is enforced by a middleware instance that never saw the block written' do
      sibling = described_class.new(app)

      status, headers, _body = sibling.call(build_env(ip: ip))

      expect(status).to eq(403)
      expect(headers['X-Request-Blocked']).to eq('true')
    end

    it 'survives a Rails.cache wipe — the block does not live there any more' do
      Rails.cache.clear

      status, = call(ip: ip)
      expect(status).to eq(403)
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

  # IMP-4f9ee46c0f50 — 2026-09-08: an operator's browser was IP-blocked by
  # opening the autonomy dashboard. The SPA issues more than 50 API calls in
  # its first seconds; every request past the 50th scored as its OWN
  # suspicious hit, ten of those arrived inside one second, and block_ip
  # fired. Two properties pin the fix: a page-load burst is at most ONE hit
  # per window (so no single page load can block anyone), and the default
  # threshold is above what a browser page load produces. A sustained flood
  # still blocks: one hit per window, ten windows.
  describe 'rapid-request bursts' do
    let(:ip) { '203.0.113.42' }

    it 'defaults the rapid-request threshold to 200 per window and reads DDOS_RAPID_REQUEST_THRESHOLD' do
      expect(described_class.rapid_request_threshold).to eq(200)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DDOS_RAPID_REQUEST_THRESHOLD').and_return('75')
      expect(described_class.rapid_request_threshold).to eq(75)
    end

    it 'scores a single burst above the threshold as ONE suspicious hit and does not block' do
      (described_class.rapid_request_threshold + 20).times { call(ip: ip) }

      expect(middleware.send(:get_suspicious_count, ip)).to eq(1)
      expect(middleware.send(:blocked?, ip)).to be(false)
      status, = call(ip: ip)
      expect(status).to eq(200)
    end

    it 'still blocks a flood that stays above the threshold across enough windows' do
      limit = RequestInspector::THRESHOLDS[:suspicious_request_limit]
      limit.times do
        (described_class.rapid_request_threshold + 5).times { call(ip: ip) }
        # next 10s window: the per-window counters expire
        Security::IpBlockStore.with do |redis|
          redis.del("#{Security::IpBlockStore::RAPID_PREFIX}#{ip}",
                    "#{Security::IpBlockStore::RAPID_FLAG_PREFIX}#{ip}")
        end
      end

      expect(middleware.send(:blocked?, ip)).to be(true)
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

  # IMP-01a0823e — the thresholds were a frozen constant while Rack::Attack,
  # the sibling control in the same request path, read its limits from
  # AdminSetting. Tuning one half of the defence meant a settings change; the
  # other half meant a redeploy.
  describe 'operator-tunable thresholds' do
    it 'reads a threshold from AdminSetting when one is set' do
      expect(described_class.threshold(:suspicious_request_limit)).to eq(10)

      AdminSetting.create!(key: 'ddos_suspicious_request_limit', value: '3', category: 'security')

      expect(described_class.threshold(:suspicious_request_limit)).to eq(3)
    end

    it 'blocks at the ADMIN-SET limit, not the compiled-in one' do
      AdminSetting.create!(key: 'ddos_suspicious_request_limit', value: '2', category: 'security')
      ip = '203.0.113.201'

      2.times { call(ip: ip, query: 'id=1 UNION SELECT password FROM users') }

      expect(middleware.send(:blocked?, ip)).to be(true)
    end

    # A typo in a settings row must not disable a security control or mint a
    # zero-second block, so a non-positive or unparseable value falls back
    # rather than being honoured.
    it 'ignores a blank, zero, negative or unparseable override' do
      %w[0 -5 abc].each do |bad|
        AdminSetting.find_or_initialize_by(key: 'ddos_suspicious_request_limit')
                    .update!(value: bad, category: 'security')
        expect(described_class.threshold(:suspicious_request_limit)).to eq(10)
      end
    end

    it 'keeps DDOS_RAPID_REQUEST_THRESHOLD ahead of the AdminSetting' do
      AdminSetting.create!(key: 'ddos_rapid_request_threshold', value: '90', category: 'security')
      expect(described_class.rapid_request_threshold).to eq(90)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DDOS_RAPID_REQUEST_THRESHOLD').and_return('75')
      expect(described_class.rapid_request_threshold).to eq(75)
    end
  end

  # This middleware runs ahead of routing, so an exception is a blank 500 with
  # nothing in the controller log, and a store that answered "blocked" on a
  # backend error would 403 the whole fleet. Both directions fail OPEN.
  describe 'when the block store is unreachable' do
    before do
      allow(Security::IpBlockStore).to receive(:pool).and_raise(Redis::CannotConnectError, 'down')
    end

    it 'serves traffic normally instead of raising or blocking' do
      status, _headers, body = call
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'reports no IP as blocked' do
      expect(middleware.send(:blocked?, '198.51.100.42')).to be(false)
    end
  end
end
