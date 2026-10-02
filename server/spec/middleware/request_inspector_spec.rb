# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

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

  def inspect_query(query)
    request = Rack::Request.new(build_env(query: query))
    middleware.send(:inspect_request, request)
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

  # 2026-09-27 hotfix — the operator was IP-blocked twice on a self-hosted hub during
  # normal UI work. Root cause: SUSPICIOUS_PATTERNS[:xss]'s event-handler
  # rule was /on\w+\s*=/i, matched against the RAW query string with no
  # markup context — it fired on ANY param whose name happens to contain
  # "on...=" (environment=, version_id=, action_category=,
  # include_decisions=, region_id=, notification_type=), each scoring 8
  # (>=5 == suspicious), and 10 such requests in an hour is a block.
  describe 'ordinary operator query strings do not false-positive' do
    # The exact param names from the incident, plus realistic query
    # strings from the approvals queue, module versions, and drift screens.
    [
      'environment=production',
      'version_id=5',
      'action_category=deploy',
      'include_decisions=true',
      'region_id=3',
      'notification_type=email',
      'status=pending&decision=approve&approver_id=42&resource_type=module',
      'module_id=abc123&version=1.2.0&diff=true&target_version_id=9&current_version_id=8',
      'drift_status=detected&node_id=xyz&severity=high&resolved=false&reconciled_at=2026-09-27'
    ].each do |query|
      it "scores #{query.inspect} as clean" do
        result = inspect_query(query)
        expect(result[:score]).to eq(0), "expected score 0, threats=#{result[:threats].inspect}"
        expect(result[:suspicious]).to be(false)
      end
    end
  end

  # Round 2 (reviewer CHANGES REQUIRED on the round-1 fix): round 1 added a
  # negative lookahead to the SQL keyword-pair rules to stop them firing on
  # free-text search-param prose ("select a region from the list"). The
  # reviewer found that lookahead disables Ruby 3.2's linear-time regex
  # matcher (100KB of repeated "select " went from 0.003s to 43.7s), and it
  # runs on POST bodies up to 10MB, pre-auth — a HIGH-severity ReDoS. That
  # change was REVERTED; the SQL-prose false positive was never the
  # reported incident (the XSS rule below was) and is tracked separately.
  # There is deliberately NO "SQL prose does not false-positive" spec here
  # any more — asserting that behavior would just re-encode the reverted,
  # unsafe fix.

  describe 'real attacks are still flagged after the false-positive fixes' do
    it 'flags an onerror handler inside an actual HTML tag' do
      result = inspect_query('q=<img src=x onerror=alert(1)>')
      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    it 'flags the URL-encoded form of the same payload (query string is decoded before matching)' do
      result = inspect_query('q=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E')
      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    # Round 2 (reviewer, finding #4): the round-1 pattern, /<[^>]*\bon[a-z]+\s*=/i,
    # stopped scanning at the FIRST '>' — including one INSIDE a quoted
    # attribute value — so it never reached "onerror=" here. The round-1
    # rule did NOT catch this; the round-2 rule (quoted-span-aware) does.
    it 'flags an onerror handler with a quoted ">" earlier in the tag (missed by the round-1 rule)' do
      round1_rule = /<[^>]*\bon[a-z]+\s*=/i
      payload = 'q=<img alt=">" onerror=alert(1)>'

      expect(payload).not_to match(round1_rule)

      result = inspect_query(payload)
      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    # Round 3 (reviewer, MEDIUM): round 2 fixed the cross-PARAMETER false
    # positive by decoding and matching each param's KEY and VALUE
    # separately, but that let an attack SPLIT ACROSS the '=' evade
    # entirely — the tag opens in the key half, the handler is in the
    # value half, and neither half alone matches.
    it 'flags a tag/handler pair split across the "=" (a tag opening in the param NAME)' do
      result = inspect_query('%3Cimg%20src=x%20onerror=alert(1)%3E')

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    # Round 3 (reviewer, LOW): Rack 3 does not treat ';' as a query
    # separator at all — splitting on /[&;]/ wrongly fragmented a ';'
    # inside an attribute value into two "params", neither of which
    # matched alone.
    it 'flags an onerror handler with a literal ";" inside a quoted attribute (";" is not a param separator)' do
      result = inspect_query('q=<img alt=";" onerror=alert(1)>')

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    it 'flags a <script> tag' do
      result = inspect_query('q=<script>alert(1)</script>')
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    it 'flags a javascript: scheme' do
      result = inspect_query('q=javascript:alert(1)')
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    it 'flags UNION SELECT' do
      result = inspect_query('id=1 UNION SELECT password FROM users')
      expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection)
    end

    # Positive coverage for the three OTHER sql_injection rules — round 2
    # (reviewer, finding #5): the only existing SQL attack spec matched via
    # the untouched UNION...SELECT branch, so nothing exercised
    # SELECT...FROM, DELETE...FROM, INSERT...INTO or UPDATE...SET at all
    # (a mutant breaking any of those three would have gone undetected).
    it 'flags SELECT...FROM, DELETE...FROM, INSERT...INTO and UPDATE...SET individually' do
      {
        'id=1 SELECT password FROM users' => 'SELECT...FROM',
        'id=1 DELETE FROM users' => 'DELETE...FROM',
        'id=1 INSERT INTO users VALUES(1)' => 'INSERT...INTO',
        "id=1 UPDATE users SET password='x'" => 'UPDATE...SET'
      }.each do |query, label|
        result = inspect_query(query)
        expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection),
          "expected #{label} (#{query.inspect}) to flag sql_injection, threats=#{result[:threats].inspect}"
      end
    end

    it 'flags path traversal' do
      result = inspect_query('file=../../../../etc/passwd')
      expect(result[:threats].map { |t| t[:type] }).to include(:path_traversal)
    end
  end

  # IMP-a09101cb2a57 — the SELECT...FROM / DELETE...FROM / INSERT...INTO /
  # UPDATE...SET rules matched any text between the two keywords, so ordinary
  # English in a free-text param ("select a region from the list") scored as
  # sql_injection and fed the progressive IP block. They now require SQL
  # STRUCTURE (a select list, a table, a clause or terminator after it) rather
  # than excluding prose, and every rule must stay on Ruby's linear-time
  # matcher: an earlier lookahead fix disabled it and 100KB of "select " took
  # 43s on a pre-auth path that reads bodies up to 10MB.
  describe 'sql_injection rules require SQL structure, not just keywords' do
    def sql_flagged?(query)
      inspect_query(query)[:threats].any? { |t| t[:type] == :sql_injection }
    end

    def sql_flagged_body?(body)
      env = Rack::MockRequest.env_for('/api/v1/widgets', method: 'POST', input: body)
      env['REMOTE_ADDR'] = '203.0.113.7'
      env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (X11; Linux x86_64)'
      env['HTTP_ACCEPT'] = 'application/json'
      middleware.send(:inspect_request, Rack::Request.new(env))[:threats].any? { |t| t[:type] == :sql_injection }
    end

    PROSE = [
      'q=select a region from the list',
      'q=select one from the list',
      'q=select+a+region+from+the+list',
      'note=update your account and set preferences',
      'note=please update the profile and set a new password',
      'q=delete from the list any item you do not need',
      'note=insert into the document a short summary',
      'q=Select an option from the dropdown to filter results',
      'note=we select items from each category and update the set',
      'q=Please select file(s) from the list below',
      'q=Select item(s) from your cart and click remove',
      'q=select Monday, Tuesday from the calendar',
      'q=SELECT a, b, c from the above and DELETE from the page',
      "q=Delete from Bob's account any old items",
      "q=select items from John's list",
      'q=choose from (select one) of the following',
      'q=The value is set from (select) menu',
      'q=insert into slide select image (jpg)'
    ].freeze

    INJECTION = [
      'id=1 SELECT password FROM users',
      'id=1 SELECT * FROM users',
      'id=1 select username, password from users where id=1',
      'id=1 SELECT COUNT(*) FROM users',
      "id=1'; SELECT password FROM users--",
      'id=1 SELECT/**/password/**/FROM/**/users',
      'id=1+SELECT+password+FROM+users',
      'id=1 DELETE FROM users',
      'id=1; DELETE FROM users WHERE 1=1',
      'id=1 INSERT INTO users VALUES(1)',
      'id=1 INSERT INTO users (name, admin) VALUES (\'x\', 1)',
      'id=1 INSERT INTO users SELECT * FROM admins',
      "id=1 UPDATE users SET password='x'",
      'id=1 UPDATE users SET admin = 1 WHERE id = 2',
      'id=1 UPDATE public.users SET admin=1',
      # What sqlmap and the common scanner corpora actually send.
      "id=1' AND (SELECT 1234 FROM (SELECT(SLEEP(5)))abcd) AND 'x'='x",
      "id=1' AND (SELECT*FROM(SELECT(SLEEP(5)))a)--",
      "id=1' AND 1=CONVERT(int,(SELECT TOP 1 table_name FROM information_schema.tables))--",
      "id=1' AND (SELECT 'a' FROM users WHERE username='administrator')='a",
      'id=1 SELECT name FROM users u WHERE 1',
      'id=1 SELECT a AS b FROM t1 WHERE 1',
      'id=1 SELECT name FROM db.`users` WHERE 1',
      'id=1 SELECT name FROM "db"."users" WHERE 1',
      'id=1 SELECT COUNT(a,b(c)) FROM t1',
      'id=1 SELECT(name)FROM(users)',
      'id=1 SELECT/***/name/***/FROM/***/users/***/WHERE/***/1',
      'id=1 INSERT INTO db.`users` VALUE(1)',
      'id=1 UPDATE users u SET admin=1',
      "id=1;SELECT username||':'||password FROM users--",
      '1;SELECT name FROM master..sysdatabases--',
      'id=1 SELECT version() FROM dual',
      "id=1 AND (SELECT sleep(5) FROM users)"
    ].freeze

    PROSE.each do |sample|
      it "does not flag prose #{sample.inspect}" do
        result = inspect_query(sample)

        expect(result[:threats].map { |t| t[:type] }).not_to include(:sql_injection)
        expect(result[:score]).to eq(0), "threats=#{result[:threats].inspect}"
      end

      it "does not flag the same prose in a POST body #{sample.inspect}" do
        expect(sql_flagged_body?(%({"q":"#{sample.sub(/\A\w+=/, '')}"}))).to be(false)
      end
    end

    INJECTION.each do |sample|
      it "still flags injection #{sample.inspect}" do
        expect(sql_flagged?(sample)).to be(true)
      end
    end

    # A per-regexp timeout was tried and rejected (each expiry leaks the matcher's
    # memoization table), so the structural rules scan a bounded prefix in
    # windows instead.
    it 'finds a payload that sits deep inside a body larger than one scan window' do
      padding = 'lorem ipsum dolor ' * 6_000 # ~108KB, past the first 64KB window
      body = %({"note":"#{padding}", "q":"1 SELECT password FROM users"})
      expect(sql_flagged_body?(body)).to be(true)
    end

    it 'does not read a cut window edge as the end of the input' do
      # "select one from inventory" is flagged at a REAL end of input (the
      # documented residue); at a window cut it must not be.
      filler = 'x' * (described_class::SQL_SCAN_WINDOW_BYTES - 22)
      body = %({"note":"#{filler} select one from inventory and more words after it"})
      expect(sql_flagged_body?(body)).to be(false)
    end

    it 'caps the structural scan: a payload past the limit is not seen, and the scan stays fast' do
      padding = 'a ' * (described_class::SQL_SCAN_LIMIT_BYTES / 2 + 4_096)
      body = %({"note":"#{padding}", "q":"1 SELECT password FROM users"})
      elapsed = Benchmark.realtime { sql_flagged_body?(body) }

      expect(elapsed).to be < 2.0
    end

    it 'bounds 10 MB of adversarial text by CPU and memory' do
      text = 'select a from t' + (' ' * 10_000_000) + 'x'
      before = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i
      elapsed = Benchmark.realtime do
        described_class::STRUCTURAL_SQL_RULES.each { |rule| middleware.send(:match_rule?, text, rule) }
      end
      after = File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i

      expect(elapsed).to be < 3.0
      expect(after - before).to be < 400_000 # KB: well under a leak-per-request
    end

    it 'keeps the UNION...SELECT, DROP...TABLE, tautology and AND/OR number rules unchanged' do
      [ 'id=1 UNION SELECT NULL', 'id=1; DROP TABLE users', "id=1 OR 1=1", 'id=1 AND 2=2' ].each do |sample|
        expect(sql_flagged?(sample)).to be(true), "expected #{sample.inspect} to flag"
      end
    end

    # Linear-time is a property of the pattern, not of a lucky input: assert it
    # for EVERY rule in every group, so a lookahead or backreference added to any
    # of them later fails here instead of in production.
    it 'every suspicious pattern is eligible for the linear-time matcher' do
      described_class::SUSPICIOUS_PATTERNS.each do |group, patterns|
        patterns.each do |pattern|
          expect(Regexp.linear_time?(pattern)).to be(true), "#{group}: #{pattern.inspect} is not linear-time"
        end
      end
    end

    it 'matches 1 MB of adversarial text in well under a second per sql rule' do
      shapes = [
        'select ' * 150_000,
        'select a,' * 120_000,
        'select a from ' * 80_000,
        'update x set ' * 90_000,
        'insert into ' * 90_000,
        'delete from ' * 90_000,
        ('/**/' * 250_000),
        ('select' + (' ' * 1_000_000)),
        'select ' + ('a, ' * 330_000)
      ]
      shapes.each do |text|
        described_class::SUSPICIOUS_PATTERNS[:sql_injection].each do |pattern|
          elapsed = Benchmark.realtime { middleware.send(:match_rule?, text, pattern) }
          expect(elapsed).to be < 1.0, "#{pattern.inspect} took #{elapsed.round(2)}s on #{text[0, 24].inspect}..."
        end
      end
    end
  end

  # Round 2 (reviewer, finding #1, HIGH): CGI.unescape("%FF") produces a
  # string with an invalid UTF-8 byte; matching a pattern against it used
  # to raise ArgumentError, which escaped inspect_request and was swallowed
  # by #call's own top-level rescue — passing the request through
  # completely UNINSPECTED (no body check, no UA check, no rate tracking).
  # A single stray %FF anywhere in the query string was a full bypass.
  describe 'invalid percent-encoded bytes cannot bypass inspection' do
    it 'does not raise on an invalid UTF-8 byte' do
      expect { inspect_query('x=%FF') }.not_to raise_error
    end

    it 'still flags a real attack elsewhere in the same query string as an invalid byte' do
      result = inspect_query('x=%FF&id=1 UNION SELECT password FROM users')

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection)
    end

    it 'still flags a real XSS attack in a different param from the invalid byte' do
      result = inspect_query('x=%FF&q=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E')

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    # Round 3 (reviewer, LOW): round 2's per-param split ran on the
    # UNSCRUBBED raw query string — a raw invalid byte already present in
    # the query string itself (not one CGI.unescape produces from a %FF)
    # raised out of String#split before decoding ever started. The string
    # is now scrubbed before it is split.
    it 'does not raise on a raw invalid UTF-8 byte in the query string itself (not percent-encoded)' do
      expect { inspect_query("\xFF&id=1") }.not_to raise_error
    end

    it 'still flags a real attack alongside a raw invalid byte in the query string itself' do
      result = inspect_query("\xFF&id=1 UNION SELECT password FROM users")

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection)
    end

    # Round 2 (reviewer, finding #1 body surface). NOTE (round 3, reviewer):
    # this spec passes identically on the pre-fix code too, so it does NOT
    # discriminate this fix from the bug — Rack::MockRequest hands back the
    # body as ASCII-8BIT (BINARY), under which no byte sequence is ever
    # "invalid", so #match? never raises here regardless of #scrub. Kept as
    # a defensive GUARD for #safe_string's use in #check_request_body (in
    # case a future Rack version, or some other caller, ever hands this
    # method a UTF-8-tagged string with a genuinely invalid byte), not as a
    # regression-pinning test — there is no known way to make body input
    # actually exercise the raise this scrubs against.
    it 'GUARD: does not raise on an invalid UTF-8 byte in the request body, and still flags a real attack in it' do
      body = "\xFF id=1 UNION SELECT password FROM users"
      env = Rack::MockRequest.env_for('/api/v1/widgets', method: 'POST', input: body)
      env['REMOTE_ADDR'] = '203.0.113.7'
      env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (X11; Linux x86_64)'
      env['HTTP_ACCEPT'] = 'application/json'

      result = nil
      expect { result = middleware.send(:inspect_request, Rack::Request.new(env)) }.not_to raise_error
      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:sql_injection)
    end
  end

  # Round 2 (reviewer, finding #3, MEDIUM): round 1 decoded the WHOLE query
  # string once and matched EVERY rule (not just xss) against the decoded
  # form, which turned ordinary encoded values into new false positives —
  # an encoded backtick/space is not an attack. Non-xss rules now run
  # against the raw, still-encoded string, same as before this hotfix.
  describe 'decoding does not introduce new false positives on non-XSS rules' do
    it 'does not flag an encoded backtick pair as command_injection' do
      result = inspect_query('q=%60rails%20console%60')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:command_injection)
      expect(result[:score]).to eq(0), "expected score 0, threats=#{result[:threats].inspect}"
    end

    it 'does not flag an encoded prose value as sql_injection' do
      result = inspect_query('q=select%20all%20items%20from%20inventory')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:sql_injection)
      expect(result[:score]).to eq(0), "expected score 0, threats=#{result[:threats].inspect}"
    end
  end

  # Round 2 (reviewer, finding #4, second half): decoding the WHOLE query
  # string as one blob let a '<' in one param's value combine with an
  # unrelated "on...=" NAME in a LATER param into a false tag match.
  # Decoding per parameter, independently, means a value can never see a
  # different param's name or value.
  describe 'a stray "<" in one param cannot combine with a different param\'s name' do
    it 'does not flag q=a<b alongside an unrelated online= param' do
      result = inspect_query('q=a%3Cb&online=true')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:xss)
      expect(result[:score]).to eq(0), "expected score 0, threats=#{result[:threats].inspect}"
    end
  end

  # Round 3 (reviewer, MEDIUM — corrected after an in-transit HTML-rendering
  # mistake in the original finding): a JSON string value can carry its
  # angle brackets as a JSON unicode escape (the six literal characters
  # backslash, u, 0, 0, 3, c / backslash, u, 0, 0, 3, e) instead of literal
  # '<'/'>'. This middleware sees the raw body ahead of any JSON.parse, so
  # those six characters are still sitting there literally; Rails' own
  # JSON parser would turn them back into '<'/'>' before the app ever saw
  # the value. The pre-hotfix rule matched a bare "on...=" substring with
  # no tag requirement, so it still caught this; the tag-context rule
  # needs an actual '<'/'>' unless it is first un-escaped.
  describe 'JSON unicode-escaped tags in a request body are still flagged' do
    def inspect_post_body(body)
      env = Rack::MockRequest.env_for('/api/v1/widgets', method: 'POST', input: body)
      env['REMOTE_ADDR'] = '203.0.113.7'
      env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (X11; Linux x86_64)'
      env['HTTP_ACCEPT'] = 'application/json'
      middleware.send(:inspect_request, Rack::Request.new(env))
    end

    # Built via Integer#chr rather than a literal backslash in this
    # source file, so the escape sequence itself can't be misread or
    # mangled while authoring the spec — the same class of mistake that
    # produced the original, incorrect version of this finding.
    def json_unicode_escaped_tag(markup)
      backslash = 92.chr
      markup.gsub("<", "#{backslash}u003c").gsub(">", "#{backslash}u003e")
    end

    it 'flags a JSON-unicode-escaped onerror handler inside a JSON string value' do
      tag = json_unicode_escaped_tag('<img src=x onerror=alert(1)>')
      result = inspect_post_body(%({"bio":"#{tag}"}))

      expect(result[:suspicious]).to be(true)
      expect(result[:threats].map { |t| t[:type] }).to include(:xss)
    end

    # Deliberate, not a gap (reviewer): an HTML-entity-escaped tag
    # (&lt;/&gt;) cannot execute as markup, so decoding it would only
    # manufacture a false positive — e.g. a user pasting escaped HTML
    # into an ordinary text field. Only the JSON unicode escape above is
    # decoded.
    it 'does not flag an HTML-entity-escaped (&lt;/&gt;) tag' do
      result = inspect_post_body('{"bio":"&lt;img src=x onerror=alert(1)&gt;"}')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:xss)
    end
  end

  # Round 3 (reviewer, LOW): two boundary cases for the xss event-handler
  # rule, both pinned deliberately rather than left as unexplained gaps.
  describe 'known limits of the xss event-handler rule' do
    # KNOWN GAP, accepted rather than chased: a stray, unpaired quote
    # before the handler defeats the quoted-span segmentation (there is no
    # partner to close the quoted alternative, and the unquoted span
    # cannot cross it either), so nothing after it can ever reach
    # "on[a-z]+\s*=". Closing this invites a broader quote-balancing
    # scheme — exactly the kind of complexity round 2 spent a ReDoS
    # incident closing off.
    it 'KNOWN GAP: does not flag an onerror handler preceded by a stray, unpaired quote' do
      result = inspect_query('q=<img src=x" onerror=alert(1)>')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:xss)
    end

    # DELIBERATE, not a gap: a bare "on...=" with no preceding '<' at all
    # is not flagged. That is the entire point of round 1 — the pre-hotfix
    # rule (/on\w+\s*=/i) matched this shape unconditionally and
    # false-positived on ordinary param names (version_id=,
    # notification_type=, ...). Pinned so a future "fix" doesn't quietly
    # reopen that incident.
    it 'DELIBERATE: does not flag a tagless "on...=" handler with no preceding "<"' do
      result = inspect_query('q=x" onfocus=alert(1)')

      expect(result[:threats].map { |t| t[:type] }).not_to include(:xss)
    end
  end

  # Round 2 (reviewer, findings #2 and #4): the round-1 lookahead disabled
  # Ruby 3.2's linear-time regex matcher for the SQL rules; the round-2 XSS
  # rule adds a quoted-span alternation and must not repeat that mistake.
  # Both are asserted to complete well inside a generous bound on
  # adversarial input designed to maximize backtracking.
  describe 'pattern matching stays linear-time (no ReDoS) on adversarial input' do
    it 'matches the XSS event-handler rule in well under half a second on 100KB of "<"' do
      input = "q=#{'<' * 100_000}"

      elapsed = Benchmark.realtime { middleware.send(:check_query_string_xss, input, { threats: [], score: 0 }) }

      expect(elapsed).to be < 0.5
    end

    it 'matches the XSS event-handler rule in well under half a second on 100KB of quote-heavy input' do
      input = "q=#{'<a \"' * 25_000}"

      elapsed = Benchmark.realtime { middleware.send(:check_query_string_xss, input, { threats: [], score: 0 }) }

      expect(elapsed).to be < 0.5
    end

    it 'matches the (reverted, unbounded) SQL rules in well under half a second on 100KB of "select "' do
      request = Rack::Request.new(build_env(query: "q=#{'select ' * 14_000}"))

      elapsed = Benchmark.realtime { middleware.send(:inspect_request, request) }

      expect(elapsed).to be < 0.5
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
