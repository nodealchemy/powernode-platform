# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the provider-wave-2 (W1) LinkedIn data-source
# template — the SAME OAuth2 Authorization-Code seam x-com-provider (I1-I6)
# built: TemplateLibrary install, a real Ai::DataSourceCredential carrying an
# oauth2_authorization_code access token, and the REAL
# Ai::DataSources::QueryService pipeline (kill flag -> quota -> cache ->
# credential broker -> sign -> dispatch -> decode -> persist -> cache write)
# against a STUBBED api.linkedin.com connection — no network, no other
# component faked.
#
# Covers:
#   1. READ (profile): the flat OpenID userinfo object wrapped as a single
#      canonical record, "Authorization: Bearer <token>" sent.
#   2. WRITE (create-post): the LinkedIn Posts API body is sent, the
#      write-safety property (never served-from/written-to the response
#      cache), and the access_token never appearing in any Rails.logger call.
RSpec.describe "LinkedIn data source (W1)", type: :service do
  # Small, self-contained Redis fake — uniquely named to avoid colliding with
  # the identically-purposed fakes in the sibling data-source integration
  # specs (see x_com_integration_spec.rb's comment on why a bare `class Foo`
  # inside a `describe` block lands at the TOP-LEVEL constant namespace).
  class LinkedinIntegrationFakeRedis
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

  FakeLinkedinResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("linkedin", account: account)[:data_source]
  end

  let(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  def stub_linkedin(status:, body:)
    response = FakeLinkedinResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(LinkedinIntegrationFakeRedis.new)
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
  # READ — profile (OpenID userinfo)
  # ==========================================================================
  describe "reading the profile endpoint" do
    it "wraps the flat userinfo object as a single canonical record and signs with the stored bearer token" do
      conn = stub_linkedin(status: 200, body: '{"sub":"abc123","name":"Jane Doe","email":"jane@example.com"}')

      envelope = query_service("profile", {}).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "sub" => "abc123", "name" => "Jane Doe", "email" => "jane@example.com" }])

      expect(conn).to have_received(:run_request) do |method, url, _body, headers|
        expect(method).to eq(:get)
        expect(url).to eq("https://api.linkedin.com/v2/userinfo")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end
  end

  # ==========================================================================
  # WRITE — create-post + write-safety (never cached, never logged)
  # ==========================================================================
  describe "writing the create-post endpoint" do
    it "sends the LinkedIn Posts API body and returns the created-post response" do
      conn = stub_linkedin(status: 201, body: '{"data":{"id":"urn:li:share:999"}}')

      envelope = query_service("create-post", { "person_id" => "42", "text" => "hello world" }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "id" => "urn:li:share:999" }])

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("https://api.linkedin.com/rest/posts")
        parsed = JSON.parse(body)
        expect(parsed["author"]).to eq("urn:li:person:42")
        expect(parsed["commentary"]).to eq("hello world")
        expect(parsed["lifecycleState"]).to eq("PUBLISHED")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end

    it "is NEVER served from cache: an identical retry re-dispatches to the upstream" do
      conn = stub_linkedin(status: 201, body: '{"data":{"id":"urn:li:share:999"}}')
      params = { "person_id" => "42", "text" => "hello world" }

      first = query_service("create-post", params).call
      second = query_service("create-post", params).call

      expect(first[:provenance][:from_cache]).to be(false)
      expect(second[:provenance][:from_cache]).to be(false)
      expect(second[:status]).to eq("success")
      expect(conn).to have_received(:run_request).twice
    end

    it "is NEVER written to the response cache" do
      stub_linkedin(status: 201, body: '{"data":{"id":"urn:li:share:999"}}')
      params = { "person_id" => "42", "text" => "hello world" }

      query_service("create-post", params).call

      endpoint = data_source.endpoints.find_by!(slug: "create-post")
      cached = Ai::DataSources::ResponseCacheService.read(data_source: data_source, endpoint: endpoint, params: params)
      expect(cached).to be_nil
    end

    it "never logs the access_token" do
      stub_linkedin(status: 201, body: '{"data":{"id":"urn:li:share:999"}}')
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      query_service("create-post", { "person_id" => "42", "text" => "hello world" }).call

      expect(logged.join("\n")).not_to include("AT-CURRENT-SECRET")
    end
  end
end
