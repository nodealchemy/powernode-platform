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
end
