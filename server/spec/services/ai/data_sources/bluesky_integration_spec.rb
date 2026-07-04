# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the provider-wave-2 (W2) Bluesky (AT Protocol) data-
# source template — the NEW atproto_app_password credential broker + the REAL
# Ai::DataSources::QueryService pipeline (kill flag -> quota -> cache ->
# credential broker -> sign -> dispatch -> decode -> persist -> cache write)
# against a STUBBED bsky.social connection — no network, no other component
# faked.
#
# Unlike the W1 OAuth2 providers (reddit/linkedin/youtube), Bluesky's
# credential carries NO pre-existing access token — the broker has to call
# com.atproto.server.createSession itself on every example, so the stubbed
# connection branches on the requested URL (session-creation vs. the actual
# API call) rather than returning one fixed response.
#
# Covers:
#   1. READ (home-timeline): canonical records mapped from the "feed" array,
#      "Authorization: Bearer <accessJwt>" sent (the accessJwt minted by the
#      broker's createSession call, never the stored app password).
#   2. WRITE (create-post): the createRecord body is sent with the caller-
#      supplied repo/text/created_at, and the write is NEVER served-from or
#      written-to the response cache; the app password never appears in any
#      Rails.logger call.
RSpec.describe "Bluesky data source (W2)", type: :service do
  # Small, self-contained Redis fake — uniquely named to avoid colliding with
  # the identically-purposed fakes in the sibling data-source integration specs
  # (see reddit_integration_spec.rb's comment on why a bare `class Foo` inside a
  # `describe` block lands at the TOP-LEVEL constant namespace).
  class BlueskyIntegrationFakeRedis
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

    # Needed here (unlike the sibling W1 fakes, which never exercise this path
    # with cached secret material present): Ai::DataSource#record_request! calls
    # redis.incrby for bandwidth tracking. Without it, a bare NoMethodError's
    # default message auto-inspects `self` (including @store) and that message
    # gets logged by QueryService#record_request_usage's rescue — which, for a
    # BrokerCache-caching broker like ours, would leak the cached accessJwt
    # sitting in @store straight into the "never logs" assertion below.
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

  FakeBlueskyResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("bluesky", account: account)[:data_source]
  end

  # Bluesky's credential carries the login pair, not a pre-existing token: the
  # generic api_key/api_secret columns hold the handle + app password.
  let(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      encrypted_api_key: "alice.bsky.social", encrypted_api_secret: "app-pw-1234-abcd-5678-efgh")
  end

  let(:access_jwt) { JWT.encode({ "exp" => 1.hour.from_now.to_i }, nil, "none") }
  let(:session_body) do
    { "did" => "did:plc:abc123", "handle" => "alice.bsky.social", "accessJwt" => access_jwt, "refreshJwt" => "RJ" }.to_json
  end

  # Branches on the requested URL: the broker's createSession call gets the
  # session body; any other URL gets the caller-supplied API response. Records
  # every dispatched request into +requests+ (method/url/body/headers) so
  # examples can assert on each call directly rather than leaning on
  # have_received's block-per-invocation semantics across MULTIPLE recorded
  # calls (this stub, unlike the sibling reddit/x-com specs, dispatches twice
  # per example: the session POST, then the actual API call).
  def stub_bluesky(api_status:, api_body:)
    session_response = FakeBlueskyResponse.new(status: 200, body: session_body, headers: { "content-type" => "application/json" })
    api_response = FakeBlueskyResponse.new(status: api_status, body: api_body, headers: { "content-type" => "application/json" })
    requests = []

    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request) do |method, url, body, headers|
      requests << { method: method, url: url, body: body, headers: headers }
      url.include?("createSession") ? session_response : api_response
    end
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    requests
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(BlueskyIntegrationFakeRedis.new)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
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
  # READ — home-timeline
  # ==========================================================================
  describe "reading the home-timeline endpoint" do
    it "brokers a session, maps canonical records from feed, and signs with the minted accessJwt" do
      body = '{"feed":[{"post":{"uri":"at://did:plc:abc/app.bsky.feed.post/1","record":{"text":"hello bluesky"}}}],"cursor":"c1"}'
      requests = stub_bluesky(api_status: 200, api_body: body)

      envelope = query_service("home-timeline", { "limit" => 25 }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq(
        [{ "post" => { "uri" => "at://did:plc:abc/app.bsky.feed.post/1", "record" => { "text" => "hello bluesky" } } }]
      )

      expect(requests.size).to eq(2)
      session_call = requests.find { |r| r[:url].include?("createSession") }
      api_call = requests.find { |r| r[:url].include?("getTimeline") }
      expect(session_call[:method]).to eq(:post)
      expect(api_call[:method]).to eq(:get)
      expect(api_call[:url]).to eq("https://bsky.social/xrpc/app.bsky.feed.getTimeline")
      expect(api_call[:headers]["Authorization"]).to eq("Bearer #{access_jwt}")
    end
  end

  # ==========================================================================
  # WRITE — create-post + write-safety (never cached, never logged)
  # ==========================================================================
  describe "writing the create-post endpoint" do
    let(:params) do
      { "repo" => "did:plc:abc123", "text" => "hello world", "created_at" => "2026-07-04T00:00:00Z" }
    end

    it "sends the createRecord body and signs with the minted accessJwt" do
      requests = stub_bluesky(api_status: 200, api_body: '{"uri":"at://did:plc:abc123/app.bsky.feed.post/1","cid":"bafy1"}')

      envelope = query_service("create-post", params).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "uri" => "at://did:plc:abc123/app.bsky.feed.post/1", "cid" => "bafy1" }])

      api_call = requests.find { |r| r[:url] == "https://bsky.social/xrpc/com.atproto.repo.createRecord" }
      expect(api_call[:method]).to eq(:post)
      parsed = JSON.parse(api_call[:body])
      expect(parsed["repo"]).to eq("did:plc:abc123")
      expect(parsed["collection"]).to eq("app.bsky.feed.post")
      expect(parsed["record"]["text"]).to eq("hello world")
      expect(parsed["record"]["createdAt"]).to eq("2026-07-04T00:00:00Z")
      expect(parsed["record"]["$type"]).to eq("app.bsky.feed.post")
      expect(api_call[:headers]["Authorization"]).to eq("Bearer #{access_jwt}")
    end

    it "is NEVER served from cache: an identical retry re-dispatches to the upstream" do
      stub_bluesky(api_status: 200, api_body: '{"uri":"at://did:plc:abc123/app.bsky.feed.post/1"}')

      first = query_service("create-post", params).call
      second = query_service("create-post", params).call

      expect(first[:provenance][:from_cache]).to be(false)
      expect(second[:provenance][:from_cache]).to be(false)
      expect(second[:status]).to eq("success")
    end

    it "is NEVER written to the response cache" do
      stub_bluesky(api_status: 200, api_body: '{"uri":"at://did:plc:abc123/app.bsky.feed.post/1"}')

      query_service("create-post", params).call

      endpoint = data_source.endpoints.find_by!(slug: "create-post")
      cached = Ai::DataSources::ResponseCacheService.read(data_source: data_source, endpoint: endpoint, params: params)
      expect(cached).to be_nil
    end

    it "never logs the app password or the minted accessJwt" do
      stub_bluesky(api_status: 200, api_body: '{"uri":"at://did:plc:abc123/app.bsky.feed.post/1"}')
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      query_service("create-post", params).call

      joined = logged.join("\n")
      expect(joined).not_to include("app-pw-1234-abcd-5678-efgh")
      expect(joined).not_to include(access_jwt)
    end
  end
end
