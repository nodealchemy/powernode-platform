# frozen_string_literal: true

require "rails_helper"

# QueryService is the Phase 1 integrator that composes the whole data-source
# pipeline (kill flag -> quota -> cache -> credential -> circuit breaker ->
# sign -> SSRF-guarded fetch -> decode -> schema validate -> normalize ->
# persist redacted audit-chained row -> cost attribution -> cache write).
#
# Every outbound HTTP call is STUBBED at the HttpConnectionFactory boundary so
# the suite is hermetic (no network). Redis is replaced with a tiny in-memory
# fake so per-source / per-agent quota counters are deterministic and the real
# ResponseCacheService (which is Redis-backed) exercises a genuine miss->hit.
RSpec.describe Ai::DataSources::QueryService, type: :service do
  # --------------------------------------------------------------------------
  # In-memory Redis fake — faithfully implements every command the DataSource
  # model quota methods, the per-agent quota counters, and the real Redis-backed
  # ResponseCacheService actually use (get/set[NX,PX,EX]/setex/mget/incr/incrby/
  # expire/pexpire/ttl/pttl/del/scan/scan_each and a result-returning MULTI whose
  # tx.* mutations land in the SAME store). Real Redis is intentionally not used
  # so the per-source / per-agent counters and the miss->hit cache path are
  # deterministic.
  #
  # NOTE: this MUST NOT be named `FakeRedis`. A bare `class FakeRedis` inside a
  # `describe` block defines the constant at TOP LEVEL, so it would collide with
  # the identically-named fake in response_cache_service_spec.rb (which uses a
  # different `@data` ivar). When both specs load, Ruby reopens the one shared
  # ::FakeRedis and the last-loaded `initialize` wins, leaving this fake's ivar
  # nil (the source of the "undefined method `[]=' for nil" failures). A unique
  # constant keeps the two fakes independent.
  class QueryServiceFakeRedis
    def initialize
      @store = {}      # key => stringified value
      @expiry = {}     # key => monotonic deadline (seconds); absent = no TTL
    end

    def get(key)
      sweep(key)
      @store[key]
    end

    # Supports plain SET and SET k v NX PX <ms> / NX EX <s> (the singleflight
    # recompute lock). Honours NX so a second acquire while the lock is live
    # fails, exactly like Redis.
    def set(key, value, nx: false, px: nil, ex: nil, **_opts)
      sweep(key)
      return nil if nx && @store.key?(key)

      @store[key] = value.to_s
      if px
        @expiry[key] = monotonic + (px.to_f / 1000.0)
      elsif ex
        @expiry[key] = monotonic + ex.to_i
      else
        @expiry.delete(key)
      end
      "OK"
    end

    def setex(key, ttl, value)
      @store[key] = value.to_s
      @expiry[key] = monotonic + ttl.to_i
      "OK"
    end

    def psetex(key, ttl_ms, value)
      @store[key] = value.to_s
      @expiry[key] = monotonic + (ttl_ms.to_f / 1000.0)
      "OK"
    end

    def mget(*keys)
      keys.flatten.map { |k| sweep(k); @store[k] }
    end

    def incr(key)
      sweep(key)
      @store[key] = (@store[key].to_i + 1).to_s
      @store[key].to_i
    end

    def incrby(key, amount)
      sweep(key)
      @store[key] = (@store[key].to_i + amount.to_i).to_s
      @store[key].to_i
    end

    def expire(key, seconds)
      return false unless @store.key?(key)

      @expiry[key] = monotonic + seconds.to_i
      true
    end

    def pexpire(key, ms)
      return false unless @store.key?(key)

      @expiry[key] = monotonic + (ms.to_f / 1000.0)
      true
    end

    def ttl(key)
      sweep(key)
      return -2 unless @store.key?(key)
      return -1 unless @expiry.key?(key)

      [(@expiry[key] - monotonic).ceil, 0].max
    end

    def pttl(key)
      sweep(key)
      return -2 unless @store.key?(key)
      return -1 unless @expiry.key?(key)

      [((@expiry[key] - monotonic) * 1000).round, 0].max
    end

    def exists?(*keys)
      keys.flatten.any? { |k| sweep(k); @store.key?(k) }
    end

    def del(*keys)
      keys.flatten.count do |k|
        @expiry.delete(k)
        !@store.delete(k).nil?
      end
    end

    def scan(_cursor, match:, count: 100)
      regex = pattern_to_regex(match)
      ["0", @store.keys.select { |k| sweep(k); @store.key?(k) && k.match?(regex) }]
    end

    def scan_each(match:, count: 100, &block)
      keys = scan("0", match: match, count: count).last
      return keys.each unless block

      keys.each(&block)
    end

    # MULTI/pipelined transaction. Yields self so the production code's
    # `tx.incr` / `tx.expire` mutate THIS same store, then returns an array of
    # each queued command's result (Redis MULTI semantics). We capture the
    # results by recording each command's return value while the block runs.
    def multi
      return [] unless block_given?

      tx = TransactionProxy.new(self)
      yield tx
      tx.results
    end
    alias pipelined multi

    # Test helper: seed a counter directly (no TTL).
    def seed(key, value)
      @store[key] = value.to_s
    end

    private

    # Thin proxy that forwards every command to the parent fake (so all writes
    # hit the same @store) while collecting return values for MULTI's result
    # array. Anything not explicitly listed is forwarded too.
    class TransactionProxy
      def initialize(parent)
        @parent = parent
        @results = []
      end

      attr_reader :results

      def method_missing(name, *args, **kwargs, &block)
        result = @parent.public_send(name, *args, **kwargs, &block)
        @results << result
        result
      end

      def respond_to_missing?(name, include_private = false)
        @parent.respond_to?(name, include_private)
      end
    end

    def pattern_to_regex(match)
      Regexp.new("\\A" + Regexp.escape(match).gsub('\*', ".*") + "\\z")
    end

    # Lazily evict an expired key so TTL semantics are observable.
    def sweep(key)
      return unless @expiry.key?(key)
      return if @expiry[key] > monotonic

      @store.delete(key)
      @expiry.delete(key)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # --------------------------------------------------------------------------
  # Faraday-like response stub returned by the stubbed connection.
  # --------------------------------------------------------------------------
  FakeResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:redis) { QueryServiceFakeRedis.new }
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:data_source) do
    create(:ai_data_source, account: account, slug: "weather_src", api_base_url: "https://api.example.com")
  end

  let(:endpoint) do
    create(:ai_data_source_endpoint, data_source: data_source, slug: "obs",
                                     path_template: "/v1/obs", response_format: "json",
                                     cache_ttl_seconds: 300)
  end

  let(:params) { { "city" => "NYC" } }

  # Default happy-path JSON body: a 2-record array.
  let(:json_body) { JSON.generate([{ "city" => "NYC", "temp" => 72 }, { "city" => "LA", "temp" => 81 }]) }

  # The absolute URL the connection is asked to fetch (built from base + path).
  let(:fetched_url) { "https://api.example.com/v1/obs" }

  # Stub the connection factory so no socket is ever opened. run_request returns
  # a Faraday-shaped response; validate_url! is neutralised (SSRF is covered in
  # the HttpConnectionFactory's own spec).
  def stub_http(response: nil, error: nil, url_for_provenance: fetched_url)
    response ||= FakeResponse.new(status: 200, body: json_body,
                                  headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    if error
      allow(conn).to receive(:run_request).and_raise(error)
    else
      allow(conn).to receive(:run_request).and_return(response)
    end
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)

    # Pin the resolved URL the service records into provenance so URL-redaction
    # assertions are deterministic regardless of template/base joining.
    allow_any_instance_of(described_class).to receive(:resolved_request_url) do |svc, _req|
      svc.instance_variable_set(:@last_absolute_url, url_for_provenance)
      url_for_provenance
    end
    conn
  end

  before do
    # All Redis access (model quota + service agent-quota + cache) hits the fake.
    allow(Powernode::Redis).to receive(:client).and_return(redis)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
    # Exercise the REAL Redis-backed ResponseCacheService end to end. Its
    # cache_enabled? gate is the `data_source_response_caching` kill flag, which
    # defaults OFF in the test env (Flipper) — turn it ON so the miss->hit path
    # (from_cache / single live fetch) is genuinely covered rather than bypassed.
    Flipper.enable(:data_source_response_caching)
  end

  after { Flipper.disable(:data_source_response_caching) }

  subject(:service) do
    described_class.new(data_source: data_source, endpoint: endpoint, params: params,
                        agent: agent, user: nil)
  end

  # ==========================================================================
  # FetchEnvelope shape (happy path)
  # ==========================================================================
  describe "FetchEnvelope shape" do
    before { stub_http }

    it "returns a success envelope with the documented top-level keys" do
      envelope = service.call

      expect(envelope).to include(
        :success, :data, :provenance, :status, :duration_ms, :bytes, :error
      )
      expect(envelope[:success]).to be(true)
      expect(envelope[:status]).to eq("success")
      expect(envelope[:error]).to be_nil
      expect(envelope[:data]).to be_an(Array)
      expect(envelope[:data].size).to eq(2)
      expect(envelope[:bytes]).to eq(json_body.bytesize)
      expect(envelope[:duration_ms]).to be >= 0
    end

    it "populates the provenance sub-hash with the documented keys" do
      prov = service.call[:provenance]

      expect(prov).to include(
        :slug, :endpoint_id, :fetched_at, :from_cache, :cache_age_seconds,
        :response_sha256, :source_url, :declared_vs_detected_content_type,
        :charset, :applied_encoding, :schema_valid, :record_count, :anomalies
      )
      expect(prov[:slug]).to eq("weather_src")
      expect(prov[:endpoint_id]).to eq(endpoint.id)
      expect(prov[:record_count]).to eq(2)
      expect(prov[:response_sha256]).to eq(Digest::SHA256.hexdigest(json_body))
      expect(prov[:anomalies]).to be_an(Array)
    end
  end

  # ==========================================================================
  # Cache miss then hit
  # ==========================================================================
  describe "cache miss then hit" do
    before { stub_http }

    it "reports from_cache:false on the first call and from_cache:true on the second" do
      first = service.call
      expect(first[:provenance][:from_cache]).to be(false)
      expect(first[:status]).to eq("success")

      # A second identical query (same data_source/endpoint/params) is served
      # from the cache the first call populated.
      second_service = described_class.new(
        data_source: data_source, endpoint: endpoint, params: params, agent: agent
      )
      second = second_service.call

      expect(second[:provenance][:from_cache]).to be(true)
      expect(second[:status]).to eq("cached")
      expect(second[:data]).to eq(first[:data])
    end

    it "only performs the live HTTP fetch once across a miss + hit" do
      conn = stub_http

      service.call
      described_class.new(
        data_source: data_source, endpoint: endpoint, params: params, agent: agent
      ).call

      # The cache hit must NOT re-dispatch to the connection.
      expect(conn).to have_received(:run_request).once
    end
  end

  # ==========================================================================
  # Per-source quota increments + quota-exceeded short-circuit
  # ==========================================================================
  describe "per-source quota accounting" do
    before { stub_http }

    it "increments the per-source minute counter after a real fetch" do
      service.call

      minute_key = "data_source:#{data_source.id}:quota:min:#{Time.current.strftime('%Y%m%d%H%M')}"
      expect(redis.get(minute_key).to_i).to be >= 1
    end

    it "increments the per-agent minute counter after a real fetch" do
      service.call

      agent_key = "data_source:#{data_source.id}:quota:#{agent.id}:min:#{Time.current.strftime('%Y%m%d%H%M')}"
      expect(redis.get(agent_key).to_i).to be >= 1
    end
  end

  describe "quota exceeded short-circuit" do
    it "returns a rate_limited envelope without dispatching when the source quota is exhausted" do
      data_source.update!(rate_limits: { "requests_per_minute" => 2 })
      # Pre-seed the source minute counter at the limit so check_quota! denies.
      minute_key = "data_source:#{data_source.id}:quota:min:#{Time.current.strftime('%Y%m%d%H%M')}"
      redis.seed(minute_key, 2)

      conn = stub_http

      envelope = service.call

      expect(envelope[:success]).to be(false)
      expect(envelope[:status]).to eq("rate_limited")
      expect(envelope[:error]).to match(/quota exceeded/i)
      expect(envelope[:retry_after]).to be_a(Integer)
      # Short-circuit: no outbound request was ever made.
      expect(conn).not_to have_received(:run_request)
    end

    it "returns rate_limited when the per-agent quota is exhausted even if the source quota allows" do
      data_source.update!(rate_limits: { "per_agent" => { "requests_per_minute" => 1 } })
      agent_key = "data_source:#{data_source.id}:quota:#{agent.id}:min:#{Time.current.strftime('%Y%m%d%H%M')}"
      redis.seed(agent_key, 1)

      conn = stub_http

      envelope = service.call

      expect(envelope[:status]).to eq("rate_limited")
      expect(envelope[:provenance][:limit]).to eq("per_agent.requests_per_minute")
      expect(conn).not_to have_received(:run_request)
    end

    it "writes a rate_limited audit row with http_status 429" do
      data_source.update!(rate_limits: { "requests_per_minute" => 1 })
      minute_key = "data_source:#{data_source.id}:quota:min:#{Time.current.strftime('%Y%m%d%H%M')}"
      redis.seed(minute_key, 1)
      stub_http

      expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)

      row = Ai::DataSourceQuery.order(created_at: :desc).first
      expect(row.status).to eq("rate_limited")
      expect(row.http_status).to eq(429)
    end
  end

  # ==========================================================================
  # SECURITY: source_url redaction of secret-bearing query params
  # ==========================================================================
  describe "provenance.source_url redaction (security)" do
    it "redacts ?api_key= AND ?token= AND ?secret= in the recorded source_url" do
      secret_url = "https://api.example.com/v1/obs?api_key=SUPERSECRET&token=abc123&secret=topsecret&city=NYC"
      stub_http(url_for_provenance: secret_url)

      envelope = service.call
      source_url = envelope[:provenance][:source_url]

      # The non-sensitive param survives.
      expect(source_url).to include("city")
      # None of the secret VALUES may appear anywhere in the recorded URL.
      expect(source_url).not_to include("SUPERSECRET")
      expect(source_url).not_to include("abc123")
      expect(source_url).not_to include("topsecret")
      # Each sensitive key is masked.
      expect(source_url).to match(/api_key=(\[REDACTED\]|%5BREDACTED%5D)/i)
      expect(source_url).to match(/token=(\[REDACTED\]|%5BREDACTED%5D)/i)
      expect(source_url).to match(/secret=(\[REDACTED\]|%5BREDACTED%5D)/i)
    end

    it "persists the redacted URL (never the raw secrets) on the query row" do
      secret_url = "https://api.example.com/v1/obs?api_key=LEAKME&token=NOPE&secret=HUSH"
      stub_http(url_for_provenance: secret_url)

      service.call
      row = Ai::DataSourceQuery.order(created_at: :desc).first

      expect(row.redacted_url).to be_present
      expect(row.redacted_url).not_to include("LEAKME")
      expect(row.redacted_url).not_to include("NOPE")
      expect(row.redacted_url).not_to include("HUSH")
      expect(row.redaction_applied).to be(true)
    end
  end

  # ==========================================================================
  # Hash-chained ai_data_source_queries row
  # ==========================================================================
  describe "audit hash-chained query row" do
    before { stub_http }

    it "writes exactly one ai_data_source_queries row for a fresh fetch" do
      expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)
    end

    it "links the query row into the SHA256 audit hash chain" do
      service.call
      row = Ai::DataSourceQuery.order(created_at: :desc).first

      anchor = row.metadata["audit_chain"]
      expect(anchor).to be_present
      expect(anchor["integrity_hash"]).to be_present
      expect(anchor["sequence_number"]).not_to be_nil
      expect(anchor["audit_log_id"]).to be_present

      # The companion AuditLog actually exists and carries the same hash.
      audit = AuditLog.find_by(id: anchor["audit_log_id"])
      expect(audit).to be_present
      expect(audit.action).to eq("api_request")
      expect(audit.integrity_hash).to eq(anchor["integrity_hash"])
    end

    it "records core forensic fields on the query row" do
      service.call
      row = Ai::DataSourceQuery.order(created_at: :desc).first

      expect(row.status).to eq("success")
      expect(row.http_status).to eq(200)
      expect(row.account_id).to eq(account.id)
      expect(row.requesting_agent_id).to eq(agent.id)
      expect(row.response_sha256).to eq(Digest::SHA256.hexdigest(json_body))
      expect(row.cached).to be(false)
      expect(row.served_stage).to eq("fresh")
      expect(row.rows_returned).to eq(2)
      expect(row.correlation_id).to be_present
    end
  end

  # ==========================================================================
  # Ai::CostAttribution emission
  # ==========================================================================
  describe "cost attribution" do
    before { stub_http }

    it "emits exactly one Ai::CostAttribution row per fetch" do
      expect { service.call }.to change(Ai::CostAttribution, :count).by(1)

      cost = Ai::CostAttribution.order(created_at: :desc).first
      expect(cost.account_id).to eq(account.id)
      expect(cost.source_type).to eq("data_source")
      expect(cost.source_id).to eq(data_source.id)
      expect(cost.cost_category).to eq("api_calls")
      expect(cost.api_calls).to eq(1)
    end

    it "prices egress from the source configuration" do
      data_source.update!(configuration: { "cost_per_request_usd" => 0.01 })

      service.call
      cost = Ai::CostAttribution.order(created_at: :desc).first
      expect(cost.amount_usd.to_f).to be >= 0.01
    end
  end

  # ==========================================================================
  # Kill flag (Flipper) short-circuit
  # ==========================================================================
  describe "kill-flag short-circuit (Flipper)" do
    let(:flag) { "data_source.#{data_source.slug}.enabled" }

    after { Flipper.remove(flag) }

    it "returns a blocked envelope and never dispatches when the source flag is present-and-disabled" do
      # Register the flag (so flag_present? is true) but leave it disabled.
      Flipper.add(flag)
      Flipper.disable(flag)

      conn = stub_http

      envelope = service.call

      expect(envelope[:success]).to be(false)
      expect(envelope[:status]).to eq("blocked")
      expect(envelope[:error]).to match(/kill flag/i)
      expect(envelope[:provenance][:anomalies]).to include("source_disabled")
      expect(conn).not_to have_received(:run_request)
    end

    it "writes a blocked audit row when killed" do
      Flipper.add(flag)
      Flipper.disable(flag)
      stub_http

      expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)
      expect(Ai::DataSourceQuery.order(created_at: :desc).first.status).to eq("blocked")
    end

    it "runs normally when the flag is unset (kill flag defaults to enabled)" do
      stub_http
      expect(service.call[:status]).to eq("success")
    end
  end

  # ==========================================================================
  # Schema validation -> provenance[:schema_valid]
  # ==========================================================================
  describe "schema validation" do
    let(:endpoint) do
      create(:ai_data_source_endpoint, :with_schema, data_source: data_source,
                                                     slug: "obs", path_template: "/v1/obs",
                                                     response_format: "json", cache_ttl_seconds: 300)
    end

    it "sets schema_valid:true when the decoded records satisfy the response_schema" do
      # temp is declared as { type: [string, number] }; JSON Schema treats a
      # plain number (Float) as the `number` type, so 72.0 satisfies the schema.
      # (The validator distinguishes integer from number, so a bare 72 would be
      # typed `integer` and fail — use a number literal to assert the happy path.)
      stub_http(response: FakeResponse.new(
        status: 200,
        body: JSON.generate([{ "city" => "NYC", "temp" => 72.0 }]),
        headers: { "content-type" => "application/json" }
      ))

      envelope = service.call
      expect(envelope[:provenance][:schema_valid]).to be(true)
      expect(envelope[:provenance][:anomalies]).not_to include("schema_invalid")
    end

    it "sets schema_valid:false and flags a schema_invalid anomaly on a violating payload" do
      # Records missing the required "city" key violate the schema.
      stub_http(response: FakeResponse.new(
        status: 200,
        body: JSON.generate([{ "temp" => 72 }]),
        headers: { "content-type" => "application/json" }
      ))

      envelope = service.call
      expect(envelope[:provenance][:schema_valid]).to be(false)
      expect(envelope[:provenance][:anomalies]).to include("schema_invalid")
    end

    it "leaves schema_valid nil (unknown) when no response_schema is configured" do
      no_schema_ep = create(:ai_data_source_endpoint, data_source: data_source,
                                                      slug: "raw", path_template: "/v1/raw",
                                                      response_format: "json", response_schema: {})
      stub_http
      svc = described_class.new(data_source: data_source, endpoint: no_schema_ep,
                                params: params, agent: agent)

      expect(svc.call[:provenance][:schema_valid]).to be_nil
    end
  end

  # ==========================================================================
  # Error mapping (never raises)
  # ==========================================================================
  describe "error handling" do
    it "maps a transport timeout to a timeout envelope without raising" do
      stub_http(error: Faraday::TimeoutError.new("execution expired"))

      envelope = service.call
      expect(envelope[:success]).to be(false)
      expect(envelope[:status]).to eq("timeout")
      expect(envelope[:error]).to be_present
    end

    it "maps a non-2xx upstream status to an error envelope and flags the anomaly" do
      stub_http(response: FakeResponse.new(status: 503, body: "down",
                                           headers: { "content-type" => "text/plain" }))

      envelope = service.call
      expect(envelope[:success]).to be(false)
      expect(envelope[:status]).to eq("error")
      expect(envelope[:provenance][:anomalies]).to include("http_503")
    end
  end

  # ==========================================================================
  # Phase 3 — stale-if-error: on a transient upstream fault, serve the
  # last-known-good cached payload (flagged) within endpoint.stale_if_error_seconds.
  #
  # The live fetch is forced to fail (timeout / 5xx) at the stubbed HTTP boundary;
  # ResponseCacheService.read_stale is stubbed to hand back a hard-expired
  # last-known-good descriptor so the substitution is deterministic and hermetic.
  # ==========================================================================
  describe "stale-if-error" do
    # A hard-expired last-known-good descriptor, as read_stale would return for an
    # entry that has passed its hard TTL but is still inside the grace window.
    let(:stale_descriptor) do
      {
        payload: {
          "data" => [{ "city" => "NYC", "temp" => 70 }],
          "provenance" => { "fetched_at" => 10.minutes.ago.utc.iso8601, "anomalies" => [] }
        },
        stale: true,
        hard_expired: true,
        age_seconds: 600,
        stale_age_seconds: 120
      }
    end

    describe "with endpoint.stale_if_error_seconds set and a prior cached value" do
      before { endpoint.update!(stale_if_error_seconds: 3600) }

      it "serves the last-known-good payload (flagged) on an upstream timeout" do
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .with(hash_including(data_source: data_source, endpoint: endpoint))
          .and_return(stale_descriptor)

        envelope = service.call

        # The transient failure is swapped for the cached good batch.
        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("cached")
        expect(envelope[:data]).to eq([{ "city" => "NYC", "temp" => 70 }])
        expect(envelope[:provenance][:from_cache]).to be(true)
        expect(envelope[:provenance][:stale_if_error]).to be(true)
        expect(envelope[:provenance][:served_on_error]).to eq("timeout")
        expect(envelope[:provenance][:anomalies]).to include("stale_if_error")
      end

      it "serves the last-known-good payload on a 5xx upstream error" do
        stub_http(response: FakeResponse.new(status: 503, body: "down",
                                             headers: { "content-type" => "text/plain" }))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor)

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("cached")
        expect(envelope[:provenance][:served_on_error]).to eq("error")
      end

      it "persists the degraded serve with served_stage 'stale_if_error' (cached:true)" do
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor)

        service.call
        row = Ai::DataSourceQuery.order(created_at: :desc).first

        expect(row.status).to eq("cached")
        expect(row.served_stage).to eq("stale_if_error")
        expect(row.cached).to be(true)
      end

      it "does NOT re-write the cache on a stale-if-error serve" do
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor)
        expect(Ai::DataSources::ResponseCacheService).not_to receive(:write)

        service.call
      end

      it "passes the error through unchanged when the stale entry is still FRESH (not hard-expired)" do
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        # A non-expired entry would have satisfied the cache layer; if we are here
        # with a fresh entry the failure is unrelated to staleness — surface it.
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor.merge(hard_expired: false, stale: false, stale_age_seconds: 0))

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("timeout")
      end

      it "passes the error through when the stale entry is older than the window" do
        endpoint.update!(stale_if_error_seconds: 60) # window shorter than the entry's stale age (120s)
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor) # stale_age_seconds: 120 > 60

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("timeout")
      end

      it "does NOT serve stale on a policy rejection (blocked) — only transient faults qualify" do
        # SSRF/egress rejection maps to STATUS_BLOCKED, which is excluded from the
        # stale-if-error statuses; the block must surface, not be masked by stale data.
        stub_http(error: Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))
        allow(Ai::DataSources::ResponseCacheService).to receive(:read_stale)
          .and_return(stale_descriptor)

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("blocked")
      end
    end

    describe "with stale_if_error_seconds nil (OFF)" do
      it "returns the error envelope unchanged and never consults read_stale" do
        # Default endpoint has stale_if_error_seconds nil.
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        expect(Ai::DataSources::ResponseCacheService).not_to receive(:read_stale)

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("timeout")
        expect(envelope[:error]).to be_present
        expect(envelope[:provenance]).not_to have_key(:stale_if_error)
      end

      it "returns a 5xx error envelope unchanged" do
        stub_http(response: FakeResponse.new(status: 503, body: "down",
                                             headers: { "content-type" => "text/plain" }))

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("error")
        expect(envelope[:provenance][:anomalies]).to include("http_503")
      end
    end
  end

  # ==========================================================================
  # Phase 2b — OPT-IN observability stages (schema drift, quality, quarantine)
  #
  # apply_observability_stages runs AFTER normalization, behind three endpoint
  # flags that ALL default false. These specs exercise each flag in isolation
  # (and the all-off baseline) against the real SchemaDriftService /
  # QualityService, with the StigmergicSignalService.emit! and the KG bridge
  # sync stubbed so nothing reaches Redis/embeddings.
  # ==========================================================================
  describe "Phase 2b opt-in observability" do
    before do
      stub_http
      # The DataSource after_commit KG sync would otherwise reach embeddings/Redis
      # when the factory persists a source under DatabaseCleaner :deletion.
      allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    end

    # ------------------------------------------------------------------------
    # track_schema -> a schema version is recorded
    # ------------------------------------------------------------------------
    describe "with endpoint.track_schema enabled" do
      before { endpoint.update!(track_schema: true) }

      it "records a schema version for the endpoint on the first tracked fetch" do
        expect { service.call }.to change { endpoint.schema_versions.count }.by(1)

        version = endpoint.schema_versions.latest_first.first
        expect(version.classification).to eq("initial")
        expect(version.version).to eq(1)
        # The inferred snapshot is the array-root shape QueryService#infer_schema emits.
        expect(version.schema).to include("type" => "array")
      end

      it "persists the drift classification onto the query row" do
        service.call

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.schema_drift).to eq("initial")
      end

      it "does NOT emit a stigmergic signal on a non-breaking (initial) classification" do
        expect_any_instance_of(Ai::Coordination::StigmergicSignalService).not_to receive(:emit!)

        service.call
      end
    end

    describe "with endpoint.track_schema and a BREAKING drift" do
      before do
        endpoint.update!(track_schema: true)
        # Seed a prior version whose field types differ from the inferred snapshot
        # so the next fetch classifies as breaking (a retyped field is breaking).
        # The live fetch infers temp -> integer (72) and city -> string; declaring
        # temp as a string previously makes the new integer a breaking type change.
        Ai::DataSources::SchemaDriftService.new(account).record_version!(
          endpoint,
          {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string" },
                "temp" => { "type" => "string" }
              }
            }
          }
        )
      end

      it "calls StigmergicSignalService.emit! with the schema-drift signal" do
        signal = instance_double(Ai::Coordination::StigmergicSignalService)
        expect(Ai::Coordination::StigmergicSignalService).to receive(:new)
          .with(account: account).and_return(signal)
        expect(signal).to receive(:emit!).with(
          hash_including(
            signal_type: "warning",
            signal_key: "data_source_schema_drift",
            payload: hash_including("classification" => "breaking")
          )
        )

        envelope = service.call

        expect(envelope[:provenance][:schema_drift]).to eq("breaking")
        expect(envelope[:provenance][:anomalies]).to include("schema_drift_breaking")
      end

      it "records the breaking classification as a second version on the query row" do
        allow_any_instance_of(Ai::Coordination::StigmergicSignalService).to receive(:emit!)

        expect { service.call }.to change { endpoint.schema_versions.count }.by(1)
        expect(Ai::DataSourceQuery.order(created_at: :desc).first.schema_drift).to eq("breaking")
      end
    end

    # ------------------------------------------------------------------------
    # quality_checks_enabled -> quality_score / quality_passed are set
    # ------------------------------------------------------------------------
    describe "with endpoint.quality_checks_enabled" do
      before { endpoint.update!(quality_checks_enabled: true) }

      it "sets quality_score and quality_passed on the envelope provenance" do
        envelope = service.call

        prov = envelope[:provenance]
        expect(prov[:quality_score]).to be_a(Float)
        expect(prov[:quality_score]).to be_between(0.0, 1.0)
        # The default 2-record happy-path body satisfies the built-in WARN rules.
        expect(prov[:quality_passed]).to be(true)
      end

      it "persists quality_score and quality_passed onto the query row" do
        service.call

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.quality_score).not_to be_nil
        expect(row.quality_score.to_f).to be_between(0.0, 1.0)
        expect(row.quality_passed).to be(true)
        expect(row.quarantined).to be(false)
      end

      it "fails quality when an ERROR-severity expectation is violated" do
        # An error-severity required_fields rule the 2-record body violates
        # (neither record carries a "humidity" key).
        create(:ai_data_source_expectation, endpoint: endpoint,
                                            name: "humidity_present", rule_type: "required_fields",
                                            severity: "error", config: { "fields" => ["humidity"] })

        envelope = service.call

        expect(envelope[:provenance][:quality_passed]).to be(false)
        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.quality_passed).to be(false)
        expect(row.quarantined).to be(false) # quarantine OFF -> bad batch still served
      end
    end

    # ------------------------------------------------------------------------
    # quarantine_on_failure + failing quality + prior cached value
    # -> serves last-known-good, does NOT cache the bad payload
    # ------------------------------------------------------------------------
    describe "with quarantine_on_failure + a failing quality + a prior cached value" do
      let(:good_payload) do
        { "data" => [{ "city" => "NYC", "humidity" => 55 }],
          "provenance" => { "fetched_at" => Time.current.utc.iso8601, "anomalies" => [] } }
      end

      before do
        endpoint.update!(quality_checks_enabled: true, quarantine_on_failure: true)
        # An error-severity rule the live (bad) batch violates.
        create(:ai_data_source_expectation, endpoint: endpoint,
                                            name: "humidity_present", rule_type: "required_fields",
                                            severity: "error", config: { "fields" => ["humidity"] })
        # Seed the last-known-good payload the quarantine path reads back.
        allow(Ai::DataSources::ResponseCacheService).to receive(:read)
          .with(hash_including(data_source: data_source, endpoint: endpoint))
          .and_return(good_payload)
      end

      it "serves the last-known-good cached batch and flags quarantined:true" do
        envelope = service.call

        expect(envelope[:provenance][:quarantined]).to be(true)
        expect(envelope[:provenance][:quality_passed]).to be(false)
        # The served data is the cached good batch, NOT the failing live batch.
        expect(envelope[:data]).to eq([{ "city" => "NYC", "humidity" => 55 }])
        expect(envelope[:provenance][:anomalies]).to include("quarantined")
      end

      it "marks the query row quarantined and does NOT cache the bad payload" do
        expect(Ai::DataSources::ResponseCacheService).not_to receive(:write)

        service.call

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.quarantined).to be(true)
        expect(row.quality_passed).to be(false)
      end
    end

    # ------------------------------------------------------------------------
    # ALL flags false (default) -> NONE of the stages run; envelope unchanged
    # ------------------------------------------------------------------------
    describe "with all observability flags false (default)" do
      it "records no schema version, emits no signal, and runs no quality" do
        # The three endpoint flags default false; assert the baseline carries zero
        # Phase-2b overhead.
        expect(endpoint.track_schema).to be(false)
        expect(endpoint.quality_checks_enabled).to be(false)
        expect(endpoint.quarantine_on_failure).to be(false)

        expect(Ai::DataSources::SchemaDriftService).not_to receive(:new)
        expect(Ai::DataSources::QualityService).not_to receive(:new)
        expect(Ai::Coordination::StigmergicSignalService).not_to receive(:new)

        expect { service.call }.not_to change(Ai::DataSourceSchemaVersion, :count)
      end

      it "leaves the Phase-2b provenance keys and query columns unset" do
        envelope = service.call

        prov = envelope[:provenance]
        expect(prov).not_to have_key(:quality_score)
        expect(prov).not_to have_key(:quality_passed)
        expect(prov).not_to have_key(:schema_drift)
        expect(prov).not_to have_key(:quarantined)

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.quality_score).to be_nil
        expect(row.quality_passed).to be_nil
        expect(row.schema_drift).to be_nil
        expect(row.quarantined).to be(false)
      end
    end
  end

  # ==========================================================================
  # Phase 4 — OUTBOUND PAGINATION
  #
  # perform_fetch branches to perform_paginated_fetch when endpoint.pagination is
  # a non-blank Hash with a supported "type" (offset/page/cursor/link). The
  # QueryService drives Ai::DataSources::Paginator, which walks multiple physical
  # requests and concatenates the decoded canonical records into ONE
  # FetchEnvelope — capped at Paginator::HARD_MAX_PAGES, re-checking the quota
  # before each subsequent page. When endpoint.pagination is blank ({}) the path
  # is OFF: exactly ONE request, and the FetchEnvelope is byte-identical to the
  # default single-request path.
  #
  # The HTTP layer is stubbed at the HttpConnectionFactory.build boundary (same
  # as stub_http) but with a connection whose run_request returns SUCCESSIVE
  # page responses in order, so the real Paginator -> dispatch_page ->
  # build->sign->dispatch path is exercised end to end (no network).
  # ==========================================================================
  describe "pagination" do
    # A JSON-array body for one page (decoded by the RestAdapter into records).
    def page_body(*records)
      JSON.generate(records)
    end

    def page_response(*records, status: 200, headers: { "content-type" => "application/json" })
      FakeResponse.new(status: status, body: page_body(*records), headers: headers)
    end

    # Stub HttpConnectionFactory.build with a connection whose run_request hands
    # back the queued page responses in order (then keeps returning the last one
    # defensively). validate_url! is neutralised; resolved_request_url is pinned
    # exactly as stub_http does so the dispatch path is hermetic and the page walk
    # is deterministic. Returns the connection double for call-count assertions.
    def stub_paginated_http(pages)
      queue = pages.dup
      conn = instance_double(Faraday::Connection)
      allow(conn).to receive(:run_request) do
        queue.length > 1 ? queue.shift : queue.first
      end
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow_any_instance_of(described_class).to receive(:resolved_request_url) do |svc, _req|
        svc.instance_variable_set(:@last_absolute_url, fetched_url)
        fetched_url
      end
      conn
    end

    describe "with endpoint.pagination configured (offset)" do
      before do
        endpoint.update!(pagination: {
                           "type" => "offset", "limit" => 2,
                           "limit_param" => "limit", "offset_param" => "offset"
                         })
      end

      it "follows multiple pages and concatenates the canonical records into ONE envelope" do
        stub_paginated_http([
                              page_response({ "id" => 1 }, { "id" => 2 }),
                              page_response({ "id" => 3 }, { "id" => 4 }),
                              page_response({ "id" => 5 }),
                              page_response # empty page -> stop
                            ])

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("success")
        # 2 + 2 + 1 records from three non-empty pages, concatenated in order.
        expect(envelope[:data].map { |r| r["id"] }).to eq([1, 2, 3, 4, 5])
        expect(envelope[:provenance][:record_count]).to eq(5)
      end

      it "dispatches one HTTP request per page until an empty page halts the walk" do
        conn = stub_paginated_http([
                                     page_response({ "id" => 1 }, { "id" => 2 }),
                                     page_response({ "id" => 3 }),
                                     page_response # empty -> stop
                                   ])

        service.call

        # Two non-empty pages + the terminating empty page = three dispatches.
        expect(conn).to have_received(:run_request).exactly(3).times
      end

      it "records the page walk on provenance and as anomalies" do
        stub_paginated_http([
                              page_response({ "id" => 1 }),
                              page_response({ "id" => 2 }),
                              page_response # empty -> stop
                            ])

        prov = service.call[:provenance]

        expect(prov[:pagination]).to include(
          type: "offset", pages_fetched: 3, truncated: false
        )
        expect(prov[:pagination][:stopped_reason]).to eq("empty_page")
        expect(prov[:anomalies]).to include("paginated_3_pages")
      end

      it "aggregates transferred bytes across all fetched pages" do
        p1 = page_response({ "id" => 1 }, { "id" => 2 })
        p2 = page_response({ "id" => 3 })
        empty = page_response
        stub_paginated_http([p1, p2, empty])

        envelope = service.call

        total = p1.body.bytesize + p2.body.bytesize + empty.body.bytesize
        expect(envelope[:bytes]).to eq(total)
      end

      it "persists a single audit-chained query row whose rows_returned spans every page" do
        stub_paginated_http([
                              page_response({ "id" => 1 }, { "id" => 2 }),
                              page_response({ "id" => 3 }),
                              page_response
                            ])

        expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.status).to eq("success")
        expect(row.rows_returned).to eq(3)
        expect(row.served_stage).to eq("fresh")
        # The single combined fetch is still tied into the audit hash chain.
        expect(row.metadata["audit_chain"]).to be_present
      end
    end

    describe "with endpoint.pagination type 'page'" do
      before { endpoint.update!(pagination: { "type" => "page", "page_param" => "p", "start_page" => 1 }) }

      it "walks successive pages and concatenates records" do
        stub_paginated_http([
                              page_response({ "id" => "a" }),
                              page_response({ "id" => "b" }),
                              page_response # empty -> stop
                            ])

        envelope = service.call

        expect(envelope[:data].map { |r| r["id"] }).to eq(%w[a b])
        expect(envelope[:provenance][:pagination][:type]).to eq("page")
      end
    end

    describe "with endpoint.pagination type 'cursor'" do
      before do
        endpoint.update!(pagination: {
                           "type" => "cursor", "cursor_param" => "after", "cursor_path" => "meta.next"
                         })
      end

      it "follows the body cursor across pages and stops when it is absent" do
        # Cursor bodies are objects; the QueryService decode path (adapter.parse)
        # unwraps a single top-level object, but the canonical records here live
        # under "data", so we map records via response_mapping records_path and
        # read the cursor from meta.next (Paginator reads the cursor off the raw
        # body independently of the record decode).
        endpoint.update!(response_mapping: { "records_path" => "data" })
        stub_paginated_http([
                              FakeResponse.new(status: 200,
                                               body: JSON.generate("data" => [{ "id" => 1 }], "meta" => { "next" => "C2" }),
                                               headers: { "content-type" => "application/json" }),
                              FakeResponse.new(status: 200,
                                               body: JSON.generate("data" => [{ "id" => 2 }], "meta" => { "next" => nil }),
                                               headers: { "content-type" => "application/json" })
                            ])

        envelope = service.call

        expect(envelope[:data].map { |r| r["id"] }).to eq([1, 2])
        expect(envelope[:provenance][:pagination][:stopped_reason]).to eq("no_cursor")
        expect(envelope[:provenance][:pagination][:pages_fetched]).to eq(2)
      end
    end

    describe "HARD_MAX_PAGES safety cap" do
      before { endpoint.update!(pagination: { "type" => "page", "max_pages" => 999 }) }

      it "never fetches more than Paginator::HARD_MAX_PAGES pages and flags truncation" do
        # Every page is non-empty so only the hard cap can halt the walk.
        many = Array.new(Ai::DataSources::Paginator::HARD_MAX_PAGES + 5) { page_response({ "id" => 1 }) }
        conn = stub_paginated_http(many)

        envelope = service.call

        expect(conn).to have_received(:run_request)
          .exactly(Ai::DataSources::Paginator::HARD_MAX_PAGES).times
        expect(envelope[:provenance][:pagination][:pages_fetched])
          .to eq(Ai::DataSources::Paginator::HARD_MAX_PAGES)
        expect(envelope[:provenance][:pagination][:truncated]).to be(true)
        expect(envelope[:provenance][:anomalies]).to include("pagination_truncated")
      end
    end

    describe "per-page quota enforcement (check_quota! before each page)" do
      before { endpoint.update!(pagination: { "type" => "page" }) }

      it "re-checks the source quota before every subsequent page" do
        stub_paginated_http([
                              page_response({ "id" => 1 }),
                              page_response({ "id" => 2 }),
                              page_response # empty -> stop after 3 fetches
                            ])
        # The model quota gate is consulted once at call() entry, then again
        # before EACH subsequent page via paginate_quota_veto -> quota_exceeded!.
        allow(data_source).to receive(:check_quota!).and_call_original

        service.call

        # 1 (call entry) + 2 (before page 2 and page 3) = at least 3 checks.
        expect(data_source).to have_received(:check_quota!).at_least(3).times
      end

      it "stops the walk early and keeps the partial result when the quota vetoes the next page" do
        stub_paginated_http([
                              page_response({ "id" => 1 }),
                              page_response({ "id" => 2 }),
                              page_response({ "id" => 3 })
                            ])
        # check_quota! is consulted at call() entry (#1, allow -> page 1 fetched),
        # then again before page 2 (#2) — deny there so the walk keeps only page 1.
        allowed = { allowed: true }
        denied  = { allowed: false, retry_after: 30, limit: "requests_per_minute" }
        call_count = 0
        allow(data_source).to receive(:check_quota!) do
          call_count += 1
          call_count <= 1 ? allowed : denied
        end

        envelope = service.call

        # Page 1 succeeded; the quota vetoed page 2, so only page 1 records remain
        # and the overall fetch is still a success (partial result is honored).
        expect(envelope[:success]).to be(true)
        expect(envelope[:data].map { |r| r["id"] }).to eq([1])
        expect(envelope[:provenance][:pagination][:pages_fetched]).to eq(1)
        expect(envelope[:provenance][:pagination][:stopped_reason]).to match(/\Aquota:/)
      end
    end

    describe "with endpoint.pagination blank (OFF — single request, unchanged envelope)" do
      it "makes exactly ONE request and never invokes the Paginator" do
        # Default endpoint pagination is {} (blank == OFF).
        expect(endpoint.pagination).to eq({})
        conn = stub_http
        expect(Ai::DataSources::Paginator).not_to receive(:new)

        service.call

        expect(conn).to have_received(:run_request).once
      end

      it "leaves the FetchEnvelope byte-identical to the default single-request path" do
        stub_http

        envelope = service.call

        # Single-page data + NO pagination provenance / pagination anomalies.
        expect(envelope[:success]).to be(true)
        expect(envelope[:data].size).to eq(2)
        expect(envelope[:bytes]).to eq(json_body.bytesize)
        expect(envelope[:provenance]).not_to have_key(:pagination)
        expect(envelope[:provenance][:anomalies]).not_to include(
          a_string_matching(/\Apaginated_/)
        )
        expect(envelope[:provenance][:anomalies]).not_to include("pagination_truncated")
      end

      it "treats a non-blank config with an UNSUPPORTED type as OFF (single request)" do
        endpoint.update!(pagination: { "type" => "soap" })
        conn = stub_http
        expect(Ai::DataSources::Paginator).not_to receive(:new)

        envelope = service.call

        expect(conn).to have_received(:run_request).once
        expect(envelope[:provenance]).not_to have_key(:pagination)
      end
    end
  end

  # ==========================================================================
  # Phase 4b-1 — CRAWL POLITENESS robots.txt GATE
  #
  # When the SOURCE opts into robots (data_source.respect_robots == true) and
  # Ai::DataSources::RobotsService disallows the resolved request path for our
  # User-Agent, QueryService short-circuits with a BLOCKED FetchEnvelope BEFORE
  # any outbound dispatch — exactly mirroring the SSRF / kill-flag blocked paths.
  # The block reason is surfaced as the "robots_disallowed" anomaly on
  # provenance (and as the envelope error). RobotsService is stubbed at the class
  # level so the gate decision is hermetic (no robots.txt fetch); only a
  # successfully-parsed Disallow returns false from #allowed?, so allowing (or
  # respect_robots OFF, the factory default) runs the normal path unchanged.
  # ==========================================================================
  describe "robots gate" do
    # A RobotsService double substituted for the one QueryService builds. We stub
    # the class .new so the service's memoized robots_service is OUR double; its
    # #allowed? verdict then drives the gate without any network robots fetch.
    let(:robots) { instance_double(Ai::DataSources::RobotsService) }

    describe "with respect_robots enabled and RobotsService DISALLOWING the path" do
      let(:data_source) do
        create(:ai_data_source, :respect_robots, account: account,
                                                 slug: "weather_src", api_base_url: "https://api.example.com")
      end

      before do
        allow(Ai::DataSources::RobotsService).to receive(:new)
          .with(data_source, agent: agent).and_return(robots)
        allow(robots).to receive(:allowed?).and_return(false)
      end

      it "returns a blocked envelope without dispatching the outbound fetch" do
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("blocked")
        # Short-circuit happens BEFORE dispatch: the connection is never invoked.
        expect(conn).not_to have_received(:run_request)
      end

      it "records the block reason (robots_disallowed) in provenance and the error" do
        stub_http

        envelope = service.call

        expect(envelope[:provenance][:anomalies]).to include("robots_disallowed")
        expect(envelope[:error]).to eq("robots_disallowed")
      end

      it "consults RobotsService#allowed? with the resolved absolute URL" do
        stub_http

        service.call

        # The gate is asked about the exact URL the service resolved (pinned by the
        # stub_http resolved_request_url override).
        expect(robots).to have_received(:allowed?).with(fetched_url)
      end

      it "persists a blocked query row (no live dispatch, so robots is a policy block)" do
        stub_http

        expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.status).to eq("blocked")
        expect(row.http_status).to be_nil
        expect(Array(row.metadata["anomalies"])).to include("robots_disallowed")
      end
    end

    describe "with respect_robots enabled but RobotsService ALLOWING the path" do
      let(:data_source) do
        create(:ai_data_source, :respect_robots, account: account,
                                                 slug: "weather_src", api_base_url: "https://api.example.com")
      end

      before do
        allow(Ai::DataSources::RobotsService).to receive(:new)
          .with(data_source, agent: agent).and_return(robots)
        allow(robots).to receive(:allowed?).and_return(true)
      end

      it "runs the normal fetch path and dispatches as usual" do
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("success")
        expect(envelope[:data].size).to eq(2)
        expect(conn).to have_received(:run_request).once
        # An allowed request carries no robots block anomaly.
        expect(envelope[:provenance][:anomalies]).not_to include("robots_disallowed")
      end
    end

    describe "with respect_robots OFF (the default source)" do
      it "never instantiates RobotsService and runs the normal path unchanged" do
        # The default :ai_data_source factory leaves respect_robots false.
        expect(data_source.respect_robots).to be(false)
        # respect_robots? short-circuits BEFORE robots_service is built, so the
        # gate is entirely skipped for a normal source.
        expect(Ai::DataSources::RobotsService).not_to receive(:new)
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("success")
        expect(conn).to have_received(:run_request).once
        expect(envelope[:provenance][:anomalies]).not_to include("robots_disallowed")
      end
    end
  end

  # ==========================================================================
  # Phase 4b-1 — INCREMENTAL CURSOR SURFACING
  #
  # After decode, when endpoint.incremental? (the +incremental+ jsonb config is
  # present), QueryService digs the NEXT high-watermark cursor out of the RAW
  # response body via Ai::DataSources::IncrementalSync.cursor_from_body(raw_body,
  # endpoint.incremental) and stashes a non-blank result into
  # provenance[:incremental_cursor]. The raw-body extraction is required because
  # the records_path unwrap discards top-level paging tokens (e.g. meta.next),
  # so they would otherwise never reach the FetchEnvelope. When the endpoint is
  # NOT incremental (the default) the key is entirely absent — the path is
  # byte-for-byte unchanged.
  # ==========================================================================
  describe "incremental cursor surfacing" do
    describe "when the endpoint is incremental and the body carries a paging token" do
      # A paging body: the canonical records live under "items"; the next cursor
      # is a TOP-LEVEL token at meta.next that the records_path unwrap discards.
      let(:paging_body) do
        JSON.generate("meta" => { "next" => "c2" }, "items" => [{ "id" => 1 }, { "id" => 2 }])
      end

      # Build the endpoint with the :incremental trait (so #incremental? is true),
      # overriding the trait's default cursor_path to the meta.next token this body
      # carries, and pinning records_path so the decoded data is the items array.
      let(:endpoint) do
        create(:ai_data_source_endpoint, :incremental, data_source: data_source,
                                                       slug: "obs", path_template: "/v1/obs",
                                                       response_format: "json", cache_ttl_seconds: 300,
                                                       incremental: { "cursor_param" => "since", "cursor_path" => "meta.next" },
                                                       response_mapping: { "records_path" => "items" })
      end

      before do
        stub_http(response: FakeResponse.new(status: 200, body: paging_body,
                                             headers: { "content-type" => "application/json" }))
      end

      it "surfaces the cursor dug from the raw body at provenance[:incremental_cursor]" do
        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:provenance][:incremental_cursor]).to eq("c2")
      end

      it "still decodes the canonical records under records_path (cursor is read off the raw body)" do
        envelope = service.call

        # The cursor extraction is independent of the records decode: the items
        # array is returned as the data, while the cursor comes from meta.next.
        expect(envelope[:data].map { |r| r["id"] }).to eq([1, 2])
        expect(envelope[:provenance][:record_count]).to eq(2)
      end

      it "omits the incremental_cursor key when the configured path is absent from the body" do
        # A body WITHOUT meta.next: cursor_from_body returns nil, so the non-blank
        # guard leaves the key off entirely (never sets it to nil).
        stub_http(response: FakeResponse.new(
          status: 200,
          body: JSON.generate("items" => [{ "id" => 9 }]),
          headers: { "content-type" => "application/json" }
        ))

        prov = service.call[:provenance]

        expect(prov).not_to have_key(:incremental_cursor)
      end
    end

    describe "when the endpoint is NOT incremental (default)" do
      before { stub_http }

      it "leaves provenance with no incremental_cursor key (path unchanged)" do
        # The default endpoint's incremental config is blank, so #incremental? is
        # false and the surfacing branch is skipped entirely.
        expect(endpoint.incremental?).to be(false)

        prov = service.call[:provenance]

        expect(prov).not_to have_key(:incremental_cursor)
      end

      it "does not call IncrementalSync.cursor_from_body" do
        expect(Ai::DataSources::IncrementalSync).not_to receive(:cursor_from_body)

        expect(service.call[:status]).to eq("success")
      end
    end
  end

  # ==========================================================================
  # Phase 4b-2a — DYNAMIC CREDENTIAL BROKERING
  #
  # When data_source.auth_config["broker"]["type"] is configured, resolve_credential
  # EXCHANGES the resolved BASE credential (static / Vault) with an external
  # authority via Ai::DataSources::Credentials::Registry.for(type).acquire(...) for a
  # SHORT-LIVED credential, just before the signed fetch. The broker returns an
  # object satisfying the SAME signer contract (#decrypted_api_key /
  # #decrypted_api_secret / #[](name)), so the signer layer is unchanged and signs
  # with the BROKERED credential. @last_credential deliberately stays pinned to the
  # BASE credential so failure/success counters track the STORED credential, not the
  # ephemeral brokered one. With NO broker configured the base credential is used
  # byte-for-byte.
  #
  # The Registry is stubbed at the class level (.for(type) -> a broker double whose
  # #acquire returns a known BrokeredCredential) so no AWS STS / OAuth / Vault call
  # is ever made; the SignerRegistry is replaced with a signer SPY so we can assert
  # exactly which credential reaches the signer. All HTTP stays stubbed at the
  # HttpConnectionFactory boundary (stub_http).
  # ==========================================================================
  describe "credential brokering" do
    # A stored BASE credential the source resolves to BEFORE brokering. A real
    # :ai_data_source_credential (Rails-encrypted) so resolve_credential's
    # active_credential lookup returns a genuine record whose #vault_path is blank
    # (so the Vault branch is skipped and we go straight to maybe_broker_credential).
    let!(:base_credential) do
      create(:ai_data_source_credential, :with_secret, account: account, data_source: data_source,
                                                       name: "base", encrypted_api_key: "BASE-KEY",
                                                       encrypted_api_secret: "BASE-SECRET")
    end

    # The SHORT-LIVED credential a broker hands back. A genuine BrokeredCredential so
    # the signer contract (#decrypted_api_key / #decrypted_api_secret / #[]) is real.
    let(:brokered_credential) do
      Ai::DataSources::Credentials::BrokeredCredential.new(
        { "api_key" => "BROKERED-TOKEN", "api_secret" => "BROKERED-SECRET" },
        expires_at: 15.minutes.from_now
      )
    end

    # A broker double conforming to the Registry CONTRACT (#acquire). Registry.for is
    # stubbed to return THIS, so no concrete broker (AWS STS / OAuth / Vault) runs.
    let(:broker) { instance_double(Ai::DataSources::Credentials::StaticBroker) }

    # A signer SPY substituted for whatever SignerRegistry.for resolves, so we can
    # assert the EXACT credential object handed to #sign! (no real signing happens).
    let(:signer_spy) { instance_double(Ai::DataSources::Auth::BearerSigner) }

    describe "with a broker configured (auth_config['broker']['type'] set)" do
      # Bearer scheme so the resolved signer is a real class we spy on; the broker
      # config lives under auth_config["broker"] exactly as broker_config reads it.
      let(:data_source) do
        create(:ai_data_source, :bearer, account: account, slug: "weather_src",
                                         api_base_url: "https://api.example.com",
                                         auth_config: { "broker" => { "type" => "oauth2_client_credentials",
                                                                      "token_url" => "https://idp.example.com/token" } })
      end

      before do
        # The configured broker type resolves to OUR double; assert it is asked to
        # exchange the BASE credential for the short-lived brokered one.
        allow(Ai::DataSources::Credentials::Registry).to receive(:for)
          .with("oauth2_client_credentials").and_return(broker)
        allow(broker).to receive(:acquire).and_return(brokered_credential)
        # Replace the resolved signer with a spy so we observe the exact credential.
        allow(Ai::DataSources::Auth::SignerRegistry).to receive(:for).and_return(signer_spy)
        allow(signer_spy).to receive(:sign!)
      end

      it "resolves the configured broker by type and exchanges the base credential" do
        stub_http

        service.call

        expect(Ai::DataSources::Credentials::Registry).to have_received(:for)
          .with("oauth2_client_credentials")
        expect(broker).to have_received(:acquire).with(
          hash_including(
            data_source: data_source,
            base_credential: base_credential,
            config: hash_including("type" => "oauth2_client_credentials")
          )
        )
      end

      it "signs the outbound request with the BROKERED credential (not the base)" do
        stub_http

        service.call

        # The signer receives the short-lived brokered credential, never the stored
        # base credential — the whole point of dynamic brokering.
        expect(signer_spy).to have_received(:sign!).with(
          anything, hash_including(credential: brokered_credential)
        )
        expect(signer_spy).not_to have_received(:sign!).with(
          anything, hash_including(credential: base_credential)
        )
      end

      it "keeps @last_credential pinned to the BASE credential so failure counters track the stored cred" do
        # Force the live fetch to fail so the perform_fetch rescue calls
        # record_failure(@last_credential, ...). @last_credential is pinned to the
        # STORED base credential in resolve_credential (NOT the brokered one), so the
        # source's failure accounting tracks the durable credential, not the ephemeral
        # token. Spy on record_failure to capture the exact credential it receives.
        stub_http(error: Faraday::TimeoutError.new("execution expired"))
        expect_any_instance_of(described_class).to receive(:record_failure)
          .with(base_credential, anything)

        envelope = service.call

        # The fetch still surfaces the transient failure (no stale config here).
        expect(envelope[:status]).to eq("timeout")
      end
    end

    describe "with NO broker configured (base credential used unchanged)" do
      # Bearer scheme, default auth_config ({} — no "broker" key), so broker_config
      # is nil and maybe_broker_credential returns the base credential untouched.
      let(:data_source) do
        create(:ai_data_source, :bearer, account: account, slug: "weather_src",
                                         api_base_url: "https://api.example.com")
      end

      before do
        allow(Ai::DataSources::Auth::SignerRegistry).to receive(:for).and_return(signer_spy)
        allow(signer_spy).to receive(:sign!)
      end

      it "never consults the broker Registry" do
        stub_http
        expect(Ai::DataSources::Credentials::Registry).not_to receive(:for)

        service.call
      end

      it "signs with the BASE credential byte-for-byte (no brokering)" do
        stub_http

        service.call

        expect(signer_spy).to have_received(:sign!).with(
          anything, hash_including(credential: base_credential)
        )
      end
    end

    describe "presigned-URL honor hook (signing SKIPPED)" do
      # A PresignedUrlBroker hands back a credential carrying a fully self-
      # authenticating URL via #presigned_url. When present, that URL IS the fetch
      # target and signing is SKIPPED entirely (the signature lives in the URL query
      # string). The override still flows through the SSRF-guarded connection.
      let(:presigned_url) do
        "https://bucket.s3.amazonaws.com/key?X-Amz-Signature=DEADBEEF&X-Amz-Expires=900"
      end

      # A BrokeredCredential whose presigned_url is present (only a PresignedUrlBroker
      # sets this field). presigned_url_for digs it out of the resolved credential.
      let(:presigned_credential) do
        Ai::DataSources::Credentials::BrokeredCredential.new(
          { "presigned_url" => presigned_url },
          expires_at: 15.minutes.from_now
        )
      end

      let(:data_source) do
        create(:ai_data_source, :bearer, account: account, slug: "weather_src",
                                         api_base_url: "https://api.example.com",
                                         auth_config: { "broker" => { "type" => "presigned_url",
                                                                      "bucket" => "bucket", "object_key" => "key" } })
      end

      before do
        allow(Ai::DataSources::Credentials::Registry).to receive(:for)
          .with("presigned_url").and_return(broker)
        allow(broker).to receive(:acquire).and_return(presigned_credential)
        # Spy on the signer so we can assert it is NEVER invoked for a presigned fetch.
        allow(Ai::DataSources::Auth::SignerRegistry).to receive(:for).and_return(signer_spy)
        allow(signer_spy).to receive(:sign!)
      end

      it "fetches the presigned URL and SKIPS signing" do
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(true)
        # The connection is asked for the presigned URL, NOT the templated endpoint URL.
        expect(conn).to have_received(:run_request)
          .with(anything, presigned_url, anything, anything)
        # Signing is skipped: the auth lives in the URL's query string, so calling the
        # signer would append a redundant/conflicting Authorization header.
        expect(signer_spy).not_to have_received(:sign!)
      end

      it "runs the normal sign-then-dispatch path when the credential has no presigned URL" do
        # A brokered credential WITHOUT a presigned_url leaves the normal path intact:
        # the signer IS invoked and the fetch targets the resolved endpoint URL.
        allow(broker).to receive(:acquire).and_return(
          Ai::DataSources::Credentials::BrokeredCredential.new({ "api_key" => "T" })
        )
        conn = stub_http

        service.call

        expect(signer_spy).to have_received(:sign!).once
        expect(conn).to have_received(:run_request)
          .with(anything, fetched_url, anything, anything)
      end
    end
  end

  # ==========================================================================
  # Phase 4b-2b — QUERY-TIME GOVERNANCE (authz gate + per-request masking)
  #
  # call() runs Ai::DataSources::GovernanceService#authorize AFTER the kill-flag
  # and quota gates but BEFORE the cache lookup / upstream fetch (step 2.5), so an
  # EXPLICIT policy deny returns a STATUS_BLOCKED envelope without ever touching
  # the cache or the network — mirroring the kill-flag / SSRF / robots blocked
  # paths. The policy decision is recorded on provenance[:policy_decision].
  #
  # On the success path finalize() computes masking ONCE via
  # GovernanceService#mask_records: the RAW (unmasked) records are persisted into
  # the audit row and written to the cache (so a later cache HIT is not pre-masked),
  # while the returned envelope carries the MASKED records and the masking outcome
  # is stamped onto provenance + the ai_data_source_queries row.
  #
  # GovernanceService is stubbed at the instance level (mirroring the file's
  # existing allow_any_instance_of style) so the gate/mask decisions are hermetic;
  # the no-governance baseline (no agent + no metadata.governance) exercises the
  # REAL service to prove the default path is byte-for-byte unchanged.
  # ==========================================================================
  describe "query-time governance (4b-2b)" do
    # ------------------------------------------------------------------------
    # AUTHZ GATE — explicit DENY short-circuits BEFORE cache + network
    # ------------------------------------------------------------------------
    describe "authorization gate DENY" do
      before do
        allow_any_instance_of(Ai::DataSources::GovernanceService).to receive(:authorize)
          .and_return({ allowed: false, reason: "nope", enforcement: "block" })
      end

      it "returns a blocked envelope without dispatching the outbound fetch" do
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(false)
        expect(envelope[:status]).to eq("blocked")
        expect(envelope[:error]).to eq("nope")
        # Short-circuit happens at the governance gate (step 2.5): the SSRF-guarded
        # connection is never built/invoked, exactly like the kill-flag block.
        expect(conn).not_to have_received(:run_request)
      end

      it "records the policy decision and a governance_blocked anomaly in provenance" do
        stub_http

        prov = service.call[:provenance]

        expect(prov[:policy_decision]).to eq(
          allowed: false, reason: "nope", enforcement: "block"
        )
        expect(prov[:anomalies]).to include("governance_blocked")
      end

      it "never consults the cache layer (a deny short-circuits before fetch)" do
        stub_http
        # The deny precedes fetch_via_cache entirely, so the response cache is never
        # read to serve — no singleflight fetch is attempted.
        expect(Ai::DataSources::ResponseCacheService).not_to receive(:fetch)

        envelope = service.call

        expect(envelope[:status]).to eq("blocked")
      end

      it "persists a blocked query row (policy block, no live dispatch)" do
        stub_http

        expect { service.call }.to change(Ai::DataSourceQuery, :count).by(1)

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.status).to eq("blocked")
        expect(row.http_status).to be_nil
        expect(row.error).to eq("nope")
        expect(Array(row.metadata["anomalies"])).to include("governance_blocked")
      end
    end

    # ------------------------------------------------------------------------
    # AUTHZ GATE — ALLOW lets the normal fetch path proceed
    # ------------------------------------------------------------------------
    describe "authorization gate ALLOW" do
      before do
        allow_any_instance_of(Ai::DataSources::GovernanceService).to receive(:authorize)
          .and_return({ allowed: true, reason: nil, enforcement: nil })
      end

      it "runs the normal fetch path and dispatches as usual" do
        conn = stub_http

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("success")
        expect(envelope[:data].size).to eq(2)
        expect(conn).to have_received(:run_request).once
        # An allowed read carries no governance block anomaly / policy decision.
        expect(envelope[:provenance][:anomalies]).not_to include("governance_blocked")
        expect(envelope[:provenance]).not_to have_key(:policy_decision)
      end
    end

    # ------------------------------------------------------------------------
    # MASKING — envelope returns MASKED records; RAW is persisted + cached
    # ------------------------------------------------------------------------
    describe "per-request masking" do
      # The RAW (unmasked) canonical records the default json_body decodes to. The
      # cache write and the audit row must see THESE, never the masked substitute.
      let(:raw_records) do
        [{ "city" => "NYC", "temp" => 72 }, { "city" => "LA", "temp" => 81 }]
      end

      before do
        # Allow the read, then force the masking outcome so the assertions are
        # deterministic regardless of the source's governance config.
        allow_any_instance_of(Ai::DataSources::GovernanceService).to receive(:authorize)
          .and_return({ allowed: true, reason: nil, enforcement: nil })
        allow_any_instance_of(Ai::DataSources::GovernanceService).to receive(:mask_records)
          .and_return({ records: [{ "x" => "MASKED" }], masking_applied: true, masked_count: 1 })
        stub_http
      end

      it "returns the MASKED records as the envelope data with masking provenance" do
        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:data]).to eq([{ "x" => "MASKED" }])
        expect(envelope[:provenance][:masking_applied]).to be(true)
        expect(envelope[:provenance][:masked_field_count]).to eq(1)
      end

      it "persists masking_applied:true on the ai_data_source_queries row" do
        service.call

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.masking_applied).to be(true)
        # rows_returned counts the RAW decoded records (the row records the real
        # fetch, not the masked envelope shape).
        expect(row.rows_returned).to eq(2)
        expect(row.metadata["masked_field_count"]).to eq(1)
      end

      it "writes the RAW (unmasked) records to the cache, never the masked payload" do
        # Spy on the cache write: finalize computes masking once but caches the RAW
        # result[:data] so a later HIT is not pre-masked (masking is per-request).
        # The cacheable payload stores records under the string "data" key; assert it
        # carries the RAW records and NOT the masked substitute.
        allow(Ai::DataSources::ResponseCacheService).to receive(:write).and_call_original

        service.call

        expect(Ai::DataSources::ResponseCacheService).to have_received(:write)
          .with(hash_including(payload: hash_including("data" => raw_records)))
        expect(Ai::DataSources::ResponseCacheService).not_to have_received(:write)
          .with(hash_including(payload: hash_including("data" => [{ "x" => "MASKED" }])))
      end
    end

    # ------------------------------------------------------------------------
    # NO-GOVERNANCE BASELINE — no agent + no metadata.governance => unchanged
    # ------------------------------------------------------------------------
    describe "no-governance path (REAL service, unchanged)" do
      # No agent AND no metadata.governance config: authorize short-circuits to
      # allow with zero policy resolution and mask_records is OFF (passthrough), so
      # the default FetchEnvelope is byte-for-byte the legacy path.
      subject(:service) do
        described_class.new(data_source: data_source, endpoint: endpoint, params: params,
                            agent: nil, user: nil)
      end

      before { stub_http }

      it "leaves the envelope data unmasked and masking_applied false on the row" do
        # Sanity: the default source carries no governance config.
        expect(data_source.metadata["governance"]).to be_nil

        envelope = service.call

        expect(envelope[:success]).to be(true)
        expect(envelope[:status]).to eq("success")
        expect(envelope[:data].size).to eq(2)
        expect(envelope[:data]).to eq([
                                        { "city" => "NYC", "temp" => 72 },
                                        { "city" => "LA", "temp" => 81 }
                                      ])
        expect(envelope[:provenance][:masking_applied]).to be(false)
        expect(envelope[:provenance][:masked_field_count]).to eq(0)

        row = Ai::DataSourceQuery.order(created_at: :desc).first
        expect(row.masking_applied).to be(false)
      end
    end
  end

  # ==========================================================================
  # (7a) CONFIG-DRIVEN TRANSFORM PIPELINE (endpoint.transforms)
  #
  # The pipeline runs AFTER NormalizationService and BEFORE the cache write /
  # persist / mask, so the TRANSFORMED shape is what is cached, persisted, and
  # returned. OFF by default (no transforms => records byte-for-byte unchanged).
  # ==========================================================================
  describe "transform pipeline" do
    # A nested body so flatten/select/computed have structure to operate on.
    let(:json_body) do
      JSON.generate([
                      { "first" => "Ada",  "last" => "Lovelace", "geo" => { "lat" => 51.5, "lon" => -0.1 } },
                      { "first" => "Alan", "last" => "Turing",   "geo" => { "lat" => 53.4, "lon" => -2.2 } }
                    ])
    end

    before { stub_http }

    it "leaves records byte-for-byte unchanged when no pipeline is configured" do
      expect(endpoint.transforms?).to be(false)

      envelope = service.call

      expect(envelope[:status]).to eq("success")
      expect(envelope[:data]).to eq([
                                      { "first" => "Ada",  "last" => "Lovelace", "geo" => { "lat" => 51.5, "lon" => -0.1 } },
                                      { "first" => "Alan", "last" => "Turing",   "geo" => { "lat" => 53.4, "lon" => -2.2 } }
                                    ])
      expect(envelope[:provenance][:transforms_applied]).to be(false)
      expect(envelope[:provenance][:record_count]).to eq(2)
    end

    it "applies an ordered flatten -> computed -> select pipeline to the canonical records" do
      endpoint.update!(transforms: {
                         "pipeline" => [
                           { "op" => "flatten" },
                           { "op" => "computed", "as" => "name", "fn" => "concat",
                             "fields" => %w[first last], "separator" => " " },
                           { "op" => "select", "fields" => %w[name geo.lat] }
                         ]
                       })
      expect(endpoint.transforms?).to be(true)

      envelope = service.call

      expect(envelope[:status]).to eq("success")
      expect(envelope[:provenance][:transforms_applied]).to be(true)
      expect(envelope[:provenance][:record_count]).to eq(2)
      expect(envelope[:data]).to eq([
                                      { "name" => "Ada Lovelace", "geo.lat" => 51.5 },
                                      { "name" => "Alan Turing",  "geo.lat" => 53.4 }
                                    ])
    end

    it "caches the TRANSFORMED shape so the next read returns it from cache" do
      endpoint.update!(transforms: {
                         "pipeline" => [{ "op" => "select", "fields" => %w[first] }]
                       })

      first = service.call
      expect(first[:provenance][:from_cache]).to be(false)
      expect(first[:data]).to eq([{ "first" => "Ada" }, { "first" => "Alan" }])

      second = described_class.new(
        data_source: data_source, endpoint: endpoint, params: params, agent: agent
      ).call

      expect(second[:provenance][:from_cache]).to be(true)
      expect(second[:status]).to eq("cached")
      # The cached payload is already transformed — no re-transform on read.
      expect(second[:data]).to eq([{ "first" => "Ada" }, { "first" => "Alan" }])
    end

    it "explodes nested arrays with unnest, fanning one record per element" do
      stub_http(response: FakeResponse.new(
        status: 200,
        body: JSON.generate([{ "id" => 1, "tags" => %w[a b] }]),
        headers: { "content-type" => "application/json" }
      ))
      endpoint.update!(transforms: {
                         "pipeline" => [{ "op" => "unnest", "field" => "tags" }]
                       })

      envelope = service.call

      expect(envelope[:provenance][:transforms_applied]).to be(true)
      expect(envelope[:provenance][:record_count]).to eq(2)
      expect(envelope[:data]).to eq([
                                      { "id" => 1, "value" => "a" },
                                      { "id" => 1, "value" => "b" }
                                    ])
    end

    it "persists the post-transform row with the transformed record count" do
      endpoint.update!(transforms: {
                         "pipeline" => [{ "op" => "select", "fields" => %w[first] }]
                       })

      service.call

      row = Ai::DataSourceQuery.order(created_at: :desc).first
      expect(row.status).to eq("success")
      expect(row.rows_returned).to eq(2)
    end

    it "falls back to untransformed records (never raises) when the pipeline faults" do
      # Force a transform fault deep in the service; the fetch must still succeed
      # with the untransformed records and transforms_applied:false.
      allow(Ai::DataSources::TransformService).to receive(:new).and_raise(StandardError, "boom")
      endpoint.update!(transforms: {
                         "pipeline" => [{ "op" => "select", "fields" => %w[first] }]
                       })

      envelope = service.call

      expect(envelope[:success]).to be(true)
      expect(envelope[:status]).to eq("success")
      expect(envelope[:provenance][:transforms_applied]).to be(false)
      expect(envelope[:data]).to eq([
                                      { "first" => "Ada",  "last" => "Lovelace", "geo" => { "lat" => 51.5, "lon" => -0.1 } },
                                      { "first" => "Alan", "last" => "Turing",   "geo" => { "lat" => 53.4, "lon" => -2.2 } }
                                    ])
      expect(envelope[:provenance][:anomalies]).to include("transform_error")
    end
  end

  # ==========================================================================
  # (2.6) DRY-RUN + PRE-EXECUTION COST ESTIMATE
  #
  # A dry-run short-circuits after the kill-flag/quota/governance gates and
  # performs NO upstream fetch, NO credential resolution/signing, NO cache write
  # and NO persistence. It returns a "dry_run" envelope with an estimate.
  # ==========================================================================
  describe "dry-run + cost estimate" do
    subject(:dry_service) do
      described_class.new(data_source: data_source, endpoint: endpoint,
                          params: params, agent: agent, dry_run: true)
    end

    it "returns a dry_run envelope with empty data and no upstream fetch" do
      conn = stub_http
      expect(conn).not_to receive(:run_request)

      envelope = dry_service.call

      expect(envelope[:status]).to eq("dry_run")
      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([])
      expect(envelope[:bytes]).to eq(0)
      expect(envelope[:error]).to be_nil
    end

    it "carries the documented estimate keys on provenance" do
      stub_http
      estimate = dry_service.call[:provenance][:estimate]

      expect(estimate).to include(
        :would_fetch, :from_cache, :source_url, :http_method,
        :estimated_cost_usd, :estimated_rows, :cache_hit_available
      )
      expect(estimate[:http_method]).to eq("GET") # endpoint factory default
    end

    it "writes NO query row and NO cache entry on a dry-run" do
      stub_http

      expect { dry_service.call }.not_to change(Ai::DataSourceQuery, :count)
      # A subsequent LIVE call must still be a cache MISS (dry-run wrote nothing).
      live = described_class.new(
        data_source: data_source, endpoint: endpoint, params: params, agent: agent
      ).call
      expect(live[:provenance][:from_cache]).to be(false)
    end

    it "reports would_fetch:false + cache_hit_available:true when a fresh cache hit exists" do
      stub_http
      # Prime the cache with a real live fetch first.
      described_class.new(
        data_source: data_source, endpoint: endpoint, params: params, agent: agent
      ).call

      estimate = dry_service.call[:provenance][:estimate]

      expect(estimate[:cache_hit_available]).to be(true)
      expect(estimate[:from_cache]).to be(true)
      expect(estimate[:would_fetch]).to be(false)
    end

    it "reports would_fetch:true + cache_hit_available:false on a cold source" do
      stub_http
      estimate = dry_service.call[:provenance][:estimate]

      expect(estimate[:cache_hit_available]).to be(false)
      expect(estimate[:would_fetch]).to be(true)
    end

    it "estimates cost from the source cost config using historical avg bytes" do
      data_source.update!(configuration: { "cost_per_request_usd" => 0.01, "cost_per_gb_usd" => 1024.0 })
      # Seed history: one successful, non-cached query that transferred ~1 MiB.
      Ai::DataSourceQuery.create!(
        data_source: data_source, endpoint: endpoint, account_id: account.id,
        status: "success", cached: false, bytes_in: 1_048_576, rows_returned: 5,
        actual_cost_usd: 0.5, http_status: 200
      )
      stub_http

      estimate = dry_service.call[:provenance][:estimate]

      # 0.01 + (1024 * (1_048_576 / 1_073_741_824)) = 0.01 + (1024 * 0.0009765625) = 1.01
      expect(estimate[:estimated_cost_usd]).to be_within(0.0001).of(1.01)
      expect(estimate[:estimated_rows]).to eq(5)
    end

    it "falls back to historical actual_cost_usd when the source declares no cost config" do
      Ai::DataSourceQuery.create!(
        data_source: data_source, endpoint: endpoint, account_id: account.id,
        status: "success", cached: false, bytes_in: 2048, rows_returned: 3,
        actual_cost_usd: 0.25, http_status: 200
      )
      stub_http

      estimate = dry_service.call[:provenance][:estimate]

      expect(estimate[:estimated_cost_usd]).to be_within(0.0001).of(0.25)
      expect(estimate[:estimated_rows]).to eq(3)
    end

    it "degrades to 0 cost and nil rows on a source with neither config nor history" do
      stub_http
      estimate = dry_service.call[:provenance][:estimate]

      expect(estimate[:estimated_cost_usd]).to eq(0.0)
      expect(estimate[:estimated_rows]).to be_nil
    end

    it "still honors the kill-flag gate (a disabled source is blocked, not dry-run)" do
      stub_http
      Flipper.enable(:"data_source.weather_src.enabled") # ensure exists
      Flipper.disable(:"data_source.weather_src.enabled")

      envelope = dry_service.call

      expect(envelope[:status]).to eq("blocked")
    end
  end
end
