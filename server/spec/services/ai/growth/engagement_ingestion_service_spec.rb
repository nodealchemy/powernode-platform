# frozen_string_literal: true

require "rails_helper"

# Growth analytics (G1): engagement ingestion drives the REAL
# Ai::DataSources::QueryService pipeline (kill flag -> quota -> cache ->
# credential broker -> sign -> dispatch -> decode -> persist -> cache write)
# against a STUBBED api.twitter.com connection — no network, no other
# component faked. Mirrors x_com_integration_spec.rb's setup.
RSpec.describe Ai::Growth::EngagementIngestionService, type: :service do
  # Uniquely-named fake Redis (see x_com_integration_spec.rb's comment on why a
  # bare `class Foo` inside a `describe` block must avoid colliding with the
  # identically-purposed fakes in other integration specs).
  class EngagementIngestionFakeRedis
    def initialize
      @store = {}
    end

    def get(key) = @store[key]

    def set(key, value, **_opts)
      @store[key] = value.to_s
      "OK"
    end

    def setex(key, _ttl, value)
      @store[key] = value.to_s
      "OK"
    end

    def mget(*keys) = keys.flatten.map { |k| @store[k] }
    def incr(key) = (@store[key] = (@store[key].to_i + 1).to_s).to_i
    def expire(_key, _seconds) = true
    def ttl(_key) = -1
    def del(*keys) = keys.flatten.count { |k| !@store.delete(k).nil? }
    def scan(_cursor, match:, count: 100) = ["0", []]
    def sadd(key, member) = ((@store[key] ||= []) << member) && 1
    def smembers(key) = Array(@store[key])

    def multi
      return [] unless block_given?

      yield self
      []
    end
    alias pipelined multi
  end

  EngagementIngestionFakeXComResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("x-com", account: account)[:data_source]
  end

  let!(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  let(:published_post) do
    endpoint = data_source.endpoints.find_by!(slug: "create-post")
    create(:ai_published_post, account: account, data_source: data_source, endpoint: endpoint,
      source_type: "x_com", external_id: "999", content: "hello world")
  end

  def stub_twitter(status:, body:)
    response = EngagementIngestionFakeXComResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(EngagementIngestionFakeRedis.new)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
  end

  describe "#ingest!" do
    it "reads engagement via the post-metrics endpoint through the governed QueryService and records a snapshot" do
      conn = stub_twitter(
        status: 200,
        body: '{"data":{"id":"999","public_metrics":{"like_count":12,"retweet_count":3,"reply_count":2,"impression_count":500}}}'
      )

      snapshot = nil
      expect do
        snapshot = described_class.new(published_post).ingest!
      end.to change(Ai::PostEngagementSnapshot, :count).by(1)

      expect(snapshot).to be_a(Ai::PostEngagementSnapshot)
      expect(snapshot.published_post).to eq(published_post)
      expect(snapshot.account_id).to eq(account.id)
      expect(snapshot.likes_count).to eq(12)
      expect(snapshot.reposts_count).to eq(3)
      expect(snapshot.replies_count).to eq(2)
      expect(snapshot.impressions_count).to eq(500)
      expect(snapshot.raw_metrics["public_metrics"]["like_count"]).to eq(12)

      expect(conn).to have_received(:run_request) do |method, url, _body, headers|
        expect(method).to eq(:get)
        expect(url).to eq("https://api.twitter.com/2/tweets/999")
        expect(headers["Authorization"]).to eq("Bearer AT-CURRENT-SECRET")
      end
    end

    it "records a second snapshot on a later poll, building a time-series" do
      stub_twitter(status: 200, body: '{"data":{"id":"999","public_metrics":{"like_count":1,"retweet_count":0,"reply_count":0,"impression_count":10}}}')
      described_class.new(published_post).ingest!

      stub_twitter(status: 200, body: '{"data":{"id":"999","public_metrics":{"like_count":5,"retweet_count":1,"reply_count":0,"impression_count":40}}}')
      described_class.new(published_post).ingest!

      expect(published_post.engagement_snapshots.count).to eq(2)
      expect(published_post.engagement_snapshots.chronological.pluck(:likes_count)).to eq([1, 5])
    end

    it "excludes a retired (inactive) data source — never dispatches the governed fetch" do
      data_source.update!(is_active: false)
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      expect(described_class.new(published_post).ingest!).to be_nil
      expect(Ai::PostEngagementSnapshot.count).to eq(0)
    end

    it "excludes a misconfigured source (requires auth but no usable credential)" do
      credential.destroy!
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      expect(described_class.new(published_post).ingest!).to be_nil
      expect(Ai::PostEngagementSnapshot.count).to eq(0)
    end

    it "skips (no raise) when the source has no engagement-metrics endpoint configured" do
      data_source.endpoints.find_by!(slug: "post-metrics").destroy!
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      expect(described_class.new(published_post).ingest!).to be_nil
    end

    it "returns nil (no snapshot) when the governed fetch itself fails" do
      stub_twitter(status: 500, body: "")

      expect(described_class.new(published_post).ingest!).to be_nil
      expect(Ai::PostEngagementSnapshot.count).to eq(0)
    end
  end

  describe ".due_posts / .sweep!" do
    it "is bounded and config-driven: an account override widens/narrows the refresh interval" do
      account.settings ||= {}
      account.update!(settings: account.settings.merge("growth_analytics" => { "engagement_refresh_interval_seconds" => 1 }))

      expect(described_class.refresh_interval_seconds(account)).to eq(1)
      expect(described_class.refresh_interval_seconds(create(:account)))
        .to eq(described_class::DEFAULT_REFRESH_INTERVAL_SECONDS)
    end

    it "sweeps every due post for an account, skipping ones with no engagement-metrics endpoint" do
      stub_twitter(status: 200, body: '{"data":{"id":"999","public_metrics":{"like_count":1,"retweet_count":0,"reply_count":0,"impression_count":1}}}')
      published_post # eager-load

      results = described_class.sweep!(account)

      expect(results.size).to eq(1)
      expect(results.first).to be_a(Ai::PostEngagementSnapshot)
    end
  end
end
