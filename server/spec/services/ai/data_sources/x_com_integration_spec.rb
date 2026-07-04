# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the x-com-provider campaign's X.com data-source
# template (I4). Installs the REAL template via TemplateLibrary, attaches a
# real Ai::DataSourceCredential carrying an oauth2_authorization_code access
# token (I1-I3's storage shape), and drives the REAL
# Ai::DataSources::QueryService pipeline (kill flag -> quota -> cache ->
# credential broker -> sign -> dispatch -> decode -> persist -> cache write)
# against a STUBBED api.twitter.com connection — no network, no other
# component faked.
#
# Covers:
#   1. READ (recent-search): canonical records mapped from "data",
#      "Authorization: Bearer <token>" sent.
#   2. WRITE (create-post): the {"text": ...} body is sent, the created-post
#      response is returned, and — the write-safety property this increment
#      adds to QueryService — the write is NEVER served-from or written-to
#      the response cache (a retried identical POST really re-dispatches
#      rather than replaying a stale cached response), and the access_token
#      never appears in any Rails.logger call.
RSpec.describe "X.com data source (I4)", type: :service do
  # Small, self-contained Redis fake (uniquely named to avoid colliding with
  # the identically-purposed fakes in query_service_spec.rb /
  # response_cache_service_spec.rb — see that file's comment on why a bare
  # `class Foo` inside a `describe` block lands at the TOP-LEVEL constant
  # namespace). Implements just what DataSource#check_quota!/#record_request!
  # and the real Redis-backed ResponseCacheService need.
  class XComIntegrationFakeRedis
    def initialize
      @store = {}
      @expiry = {}
    end

    def get(key)
      sweep(key)
      @store[key]
    end

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

    def mget(*keys)
      keys.flatten.map { |k| sweep(k); @store[k] }
    end

    def incr(key)
      sweep(key)
      @store[key] = (@store[key].to_i + 1).to_s
      @store[key].to_i
    end

    def expire(key, seconds)
      return false unless @store.key?(key)

      @expiry[key] = monotonic + seconds.to_i
      true
    end

    def ttl(key)
      sweep(key)
      return -2 unless @store.key?(key)
      return -1 unless @expiry.key?(key)

      [(@expiry[key] - monotonic).ceil, 0].max
    end

    def del(*keys)
      keys.flatten.count do |k|
        @expiry.delete(k)
        !@store.delete(k).nil?
      end
    end

    def scan(_cursor, match:, count: 100)
      regex = Regexp.new("\\A" + Regexp.escape(match).gsub('\*', ".*") + "\\z")
      ["0", @store.keys.select { |k| sweep(k); @store.key?(k) && k.match?(regex) }]
    end

    def sadd(key, member)
      sweep(key)
      (@store[key] ||= []) << member unless (@store[key] || []).include?(member)
      1
    end

    def smembers(key)
      sweep(key)
      Array(@store[key])
    end

    def multi
      return [] unless block_given?

      tx = TransactionProxy.new(self)
      yield tx
      tx.results
    end
    alias pipelined multi

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

    private

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

  FakeXComResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("x-com", account: account)[:data_source]
  end

  let(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  def stub_twitter(status:, body:)
    response = FakeXComResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    # Installing the template persists a real Ai::DataSource whose after_commit
    # fires a knowledge-graph re-sync — stub it exactly like template_library_spec
    # so persistence never reaches Redis/embeddings.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(XComIntegrationFakeRedis.new)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
    # Exercise the REAL Redis-backed ResponseCacheService (default OFF in test).
    Flipper.enable(:data_source_response_caching)
    credential # eager-load: data_source + credential exist before each example
  end

  after { Flipper.disable(:data_source_response_caching) }

  def query_service(endpoint_slug, params)
    endpoint = data_source.endpoints.find_by!(slug: endpoint_slug)
    Ai::DataSources::QueryService.new(
      data_source: data_source, endpoint: endpoint, params: params, agent: agent, user: nil
    )
  end

  # ==========================================================================
  # READ — recent-search
  # ==========================================================================
  describe "reading the recent-search endpoint" do
    it "maps canonical records from \"data\" and signs the request with the stored bearer token" do
      conn = stub_twitter(status: 200, body: '{"data":[{"id":"1","text":"hello from X"}]}')

      envelope = query_service("recent-search", { "query" => "from:openai" }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "id" => "1", "text" => "hello from X" }])

      expect(conn).to have_received(:run_request) do |method, url, _body, headers|
        expect(method).to eq(:get)
        expect(url).to eq("https://api.twitter.com/2/tweets/search/recent")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end
  end

  # ==========================================================================
  # WRITE — create-post + write-safety (never cached, never deduped)
  # ==========================================================================
  describe "writing the create-post endpoint" do
    it "sends the {text:} body and returns the created-post response" do
      conn = stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')

      envelope = query_service("create-post", { "text" => "hello world" }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "id" => "999", "text" => "hello world" }])

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("https://api.twitter.com/2/tweets")
        expect(JSON.parse(body)).to eq("text" => "hello world")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end

    it "is NEVER served from cache: an identical retry re-dispatches to the upstream" do
      conn = stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')

      first = query_service("create-post", { "text" => "hello world" }).call
      second = query_service("create-post", { "text" => "hello world" }).call

      expect(first[:provenance][:from_cache]).to be(false)
      expect(second[:provenance][:from_cache]).to be(false)
      expect(second[:status]).to eq("success") # never "cached"
      expect(conn).to have_received(:run_request).twice
    end

    it "is NEVER written to the response cache" do
      stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')
      params = { "text" => "hello world" }

      query_service("create-post", params).call

      endpoint = data_source.endpoints.find_by!(slug: "create-post")
      cached = Ai::DataSources::ResponseCacheService.read(data_source: data_source, endpoint: endpoint, params: params)
      expect(cached).to be_nil
    end

    it "never logs the access_token" do
      stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      query_service("create-post", { "text" => "hello world" }).call

      expect(logged.join("\n")).not_to include("AT-CURRENT-SECRET")
    end
  end
end
