# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the provider-wave-2 (W1) Reddit data-source
# template — the SAME OAuth2 Authorization-Code seam x-com-provider (I1-I6)
# built: TemplateLibrary install, a real Ai::DataSourceCredential carrying an
# oauth2_authorization_code access token, and the REAL
# Ai::DataSources::QueryService pipeline (kill flag -> quota -> cache ->
# credential broker -> sign -> dispatch -> decode -> persist -> cache write)
# against a STUBBED oauth.reddit.com connection — no network, no other
# component faked.
#
# Covers:
#   1. READ (subreddit-new): canonical records mapped from the nested Reddit
#      "Listing" shape ("data.children"), "Authorization: Bearer <token>" sent.
#   2. WRITE (submit-post): the submit body is sent, the created-post response
#      is mapped from "json.data", and — the write-safety property this seam
#      guarantees — the write is NEVER served-from or written-to the response
#      cache, and the access_token never appears in any Rails.logger call.
RSpec.describe "Reddit data source (W1)", type: :service do
  # Small, self-contained Redis fake — uniquely named to avoid colliding with
  # the identically-purposed fakes in the sibling data-source integration
  # specs (see x_com_integration_spec.rb's comment on why a bare `class Foo`
  # inside a `describe` block lands at the TOP-LEVEL constant namespace).
  class RedditIntegrationFakeRedis
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

  FakeRedditResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("reddit", account: account)[:data_source]
  end

  let(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  def stub_reddit(status:, body:)
    response = FakeRedditResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(RedditIntegrationFakeRedis.new)
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
  # READ — subreddit-new
  # ==========================================================================
  describe "reading the subreddit-new endpoint" do
    it "maps canonical records from the Listing's data.children and signs with the stored bearer token" do
      body = '{"kind":"Listing","data":{"children":[' \
             '{"kind":"t3","data":{"id":"abc","title":"hello reddit"}}' \
             ']}}'
      conn = stub_reddit(status: 200, body: body)

      envelope = query_service("subreddit-new", { "subreddit" => "test", "limit" => 25 }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "kind" => "t3", "data" => { "id" => "abc", "title" => "hello reddit" } }])

      expect(conn).to have_received(:run_request) do |method, url, _body, headers|
        expect(method).to eq(:get)
        expect(url).to eq("https://oauth.reddit.com/r/test/new")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end
  end

  # ==========================================================================
  # WRITE — submit-post + write-safety (never cached, never logged)
  # ==========================================================================
  describe "writing the submit-post endpoint" do
    it "sends the submit body and returns the created-post response mapped from json.data" do
      conn = stub_reddit(status: 200, body: '{"json":{"errors":[],"data":{"id":"t3_999","name":"t3_999"}}}')

      envelope = query_service("submit-post", {
        "subreddit" => "test", "title" => "hello", "text" => "world"
      }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "id" => "t3_999", "name" => "t3_999" }])

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("https://oauth.reddit.com/api/submit")
        parsed = JSON.parse(body)
        expect(parsed["sr"]).to eq("test")
        expect(parsed["title"]).to eq("hello")
        expect(parsed["text"]).to eq("world")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end

    it "is NEVER served from cache: an identical retry re-dispatches to the upstream" do
      conn = stub_reddit(status: 200, body: '{"json":{"errors":[],"data":{"id":"t3_999"}}}')
      params = { "subreddit" => "test", "title" => "hello", "text" => "world" }

      first = query_service("submit-post", params).call
      second = query_service("submit-post", params).call

      expect(first[:provenance][:from_cache]).to be(false)
      expect(second[:provenance][:from_cache]).to be(false)
      expect(second[:status]).to eq("success")
      expect(conn).to have_received(:run_request).twice
    end

    it "is NEVER written to the response cache" do
      stub_reddit(status: 200, body: '{"json":{"errors":[],"data":{"id":"t3_999"}}}')
      params = { "subreddit" => "test", "title" => "hello", "text" => "world" }

      query_service("submit-post", params).call

      endpoint = data_source.endpoints.find_by!(slug: "submit-post")
      cached = Ai::DataSources::ResponseCacheService.read(data_source: data_source, endpoint: endpoint, params: params)
      expect(cached).to be_nil
    end

    it "never logs the access_token" do
      stub_reddit(status: 200, body: '{"json":{"errors":[],"data":{"id":"t3_999"}}}')
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      query_service("submit-post", { "subreddit" => "test", "title" => "hello", "text" => "world" }).call

      expect(logged.join("\n")).not_to include("AT-CURRENT-SECRET")
    end
  end
end
