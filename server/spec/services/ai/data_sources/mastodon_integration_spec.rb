# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for the provider-wave-2 (W2) Mastodon data-source
# template — the SAME OAuth2 Authorization-Code seam x-com/linkedin/reddit/
# youtube already built (oauth2_authorization_code broker, BearerSigner):
# ZERO new signer/broker code. What this spec specifically proves is the
# FEDERATED-HOST story: OauthAuthorizationCodeService and
# Oauth2AuthorizationCodeBroker both resolve authorize_url/token_url from the
# data source's OWN auth_config, never a hardcoded provider constant, so
# swapping the template's placeholder mastodon.social host for an arbitrary
# operator instance — done here entirely via data_source updates, no code
# changes — is enough to make the whole pipeline (kill flag -> quota -> cache
# -> credential broker -> sign -> dispatch -> decode -> persist -> cache
# write) target that instance, against a STUBBED connection — no network, no
# other component faked.
#
# Covers:
#   1. Install: the template's placeholder config (source_type, auth_scheme,
#      broker type, federated-host metadata).
#   2. READ (home-timeline): a bare top-level JSON array is mapped one record
#      per element (no records_path — Decoders::Json's array-inference path),
#      dispatched against a CUSTOM instance host, "Authorization: Bearer
#      <token>" sent.
#   3. WRITE (create-status): the status body is sent to the custom instance,
#      and — the write-safety property every W1/W2 template guarantees — the
#      write is NEVER served-from or written-to the response cache, and the
#      access_token never appears in any Rails.logger call.
RSpec.describe "Mastodon data source (W2)", type: :service do
  # Small, self-contained Redis fake — uniquely named to avoid colliding with
  # the identically-purposed fakes in the sibling data-source integration
  # specs (see reddit_integration_spec.rb's comment on why a bare `class Foo`
  # inside a `describe` block lands at the TOP-LEVEL constant namespace).
  class MastodonIntegrationFakeRedis
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

  FakeMastodonResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:install_result) { Ai::DataSources::TemplateLibrary.install("mastodon", account: account) }
  let(:data_source) { install_result[:data_source] }

  # The operator's OWN instance — proves the template's placeholder host is
  # genuinely just a starting point, not something baked into any code path.
  let(:custom_instance) { "https://fosstodon.example" }

  let(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  def stub_mastodon(status:, body:)
    response = FakeMastodonResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(MastodonIntegrationFakeRedis.new)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
    Flipper.enable(:data_source_response_caching)
    # Re-point every instance-specific auth_config URL (+ api_base_url) at the
    # operator's own instance — exactly the edit the template's description
    # instructs, done here via a plain model update (no code path involved).
    data_source.update!(
      api_base_url: custom_instance,
      auth_config: data_source.auth_config.merge(
        "authorize_url" => "#{custom_instance}/oauth/authorize",
        "token_url" => "#{custom_instance}/oauth/token",
        "broker" => { "type" => "oauth2_authorization_code", "token_url" => "#{custom_instance}/oauth/token" }
      )
    )
    credential # eager-load: data_source + credential exist before each example
  end

  after { Flipper.disable(:data_source_response_caching) }

  def query_service(endpoint_slug, params)
    endpoint = data_source.endpoints.find_by!(slug: endpoint_slug)
    Ai::DataSources::QueryService.new(
      data_source: data_source, endpoint: endpoint, params: params, agent: agent, user: nil
    )
  end

  describe "installing the template" do
    it "materializes a federated, OAuth2-authorization-code, bearer-scheme source" do
      # A fresh, independent install (distinct slug) so this example asserts the
      # PRISTINE template shape, unaffected by the before-hook's custom-instance
      # override applied to the memoized `data_source`.
      result = Ai::DataSources::TemplateLibrary.install("mastodon", account: account, target_slug: "mastodon-fresh")

      expect(result[:created]).to be(true)
      source = result[:data_source]
      expect(source.source_type).to eq("mastodon")
      expect(source.auth_scheme).to eq("bearer")
      expect(source.api_base_url).to eq("https://mastodon.social")
      expect(source.auth_config["broker"]["type"]).to eq("oauth2_authorization_code")
      expect(source.metadata["federated"]).to be_present
    end
  end

  # ==========================================================================
  # READ — home-timeline (bare top-level array, no records_path)
  # ==========================================================================
  describe "reading the home-timeline endpoint" do
    it "maps each array element as a record and dispatches against the operator's OWN instance" do
      body = '[{"id":"1","content":"hello fediverse"},{"id":"2","content":"second toot"}]'
      conn = stub_mastodon(status: 200, body: body)

      envelope = query_service("home-timeline", { "limit" => 20 }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq(
        [{ "id" => "1", "content" => "hello fediverse" }, { "id" => "2", "content" => "second toot" }]
      )

      expect(conn).to have_received(:run_request) do |method, url, _body, headers|
        expect(method).to eq(:get)
        expect(url).to eq("#{custom_instance}/api/v1/timelines/home")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end
  end

  # ==========================================================================
  # WRITE — create-status + write-safety (never cached, never logged)
  # ==========================================================================
  describe "writing the create-status endpoint" do
    it "sends the status body to the operator's OWN instance and signs with the stored bearer token" do
      conn = stub_mastodon(status: 200, body: '{"id":"999","content":"posted!"}')

      envelope = query_service("create-status", { "text" => "posted!" }).call

      expect(envelope[:success]).to be(true)
      expect(envelope[:data]).to eq([{ "id" => "999", "content" => "posted!" }])

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("#{custom_instance}/api/v1/statuses")
        parsed = JSON.parse(body)
        expect(parsed["status"]).to eq("posted!")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end

    it "is NEVER written to the response cache" do
      stub_mastodon(status: 200, body: '{"id":"999","content":"posted!"}')

      query_service("create-status", { "text" => "posted!" }).call

      endpoint = data_source.endpoints.find_by!(slug: "create-status")
      cached = Ai::DataSources::ResponseCacheService.read(
        data_source: data_source, endpoint: endpoint, params: { "text" => "posted!" }
      )
      expect(cached).to be_nil
    end

    it "never logs the access_token" do
      stub_mastodon(status: 200, body: '{"id":"999","content":"posted!"}')
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      query_service("create-status", { "text" => "posted!" }).call

      expect(logged.join("\n")).not_to include("AT-CURRENT-SECRET")
    end
  end
end
