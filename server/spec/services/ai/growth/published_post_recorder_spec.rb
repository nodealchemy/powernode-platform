# frozen_string_literal: true

require "rails_helper"

# Growth analytics (G1): a successful write against an endpoint opted into
# metadata["captures_published_post"] (x-com's "Create post") is recorded as
# an Ai::PublishedPost. Exercised end-to-end through
# Ai::Tools::DataSourceTool#guarded_fetch — the SAME choke point every agent
# write dispatch already passes through (see the "write endpoint gate"
# describe block in data_source_tool_spec.rb) — against a STUBBED
# api.twitter.com connection, mirroring x_com_integration_spec.rb.
RSpec.describe Ai::Growth::PublishedPostRecorder, type: :service do
  class PublishedPostRecorderFakeRedis
    def initialize
      @store = {}
    end

    def get(key) = @store[key]
    def set(key, value, **_opts) = (@store[key] = value.to_s) && "OK"
    def setex(key, _ttl, value) = (@store[key] = value.to_s) && "OK"
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

  PublishedPostRecorderFakeXComResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:user) { create(:user, account: account, permissions: ["ai.data_sources.manage"]) }

  let(:data_source) do
    Ai::DataSources::TemplateLibrary.install("x-com", account: account)[:data_source]
  end

  let!(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "oauth-client-id", client_secret: "oauth-client-secret",
      encrypted_access_token: "AT-CURRENT-SECRET", encrypted_refresh_token: "RT-CURRENT-SECRET",
      access_token_expires_at: 1.hour.from_now)
  end

  def stub_twitter(status:, body:)
    response = PublishedPostRecorderFakeXComResponse.new(status: status, body: body, headers: { "content-type" => "application/json" })
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    allow(Powernode::Redis).to receive(:client).and_return(PublishedPostRecorderFakeRedis.new)
    Ai::CircuitBreakerRegistry.clear! if Ai::CircuitBreakerRegistry.respond_to?(:clear!)
    credential # eager-load: data_source + credential exist before each example
    user # eager-load: grant ai.data_sources.manage before the tool call
  end

  def publish(text)
    tool = Ai::Tools::DataSourceTool.new(account: account, agent: agent, user: user)
    tool.execute(params: {
      action: "data_source_query", data_source_id: "x-com",
      endpoint_id: "create-post", params: { "text" => text }
    })
  end

  it "records an Ai::PublishedPost off a successful create-post write" do
    stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')

    result = nil
    expect { result = publish("hello world") }.to change(Ai::PublishedPost, :count).by(1)

    expect(result[:success]).to be(true)
    post = Ai::PublishedPost.last
    expect(post.account).to eq(account)
    expect(post.data_source).to eq(data_source)
    expect(post.endpoint.slug).to eq("create-post")
    expect(post.requesting_agent).to eq(agent)
    expect(post.source_type).to eq("x_com")
    expect(post.external_id).to eq("999")
    expect(post.content).to eq("hello world")
    expect(post.published_at).to be_present
  end

  it "is idempotent on [data_source, external_id] — a retried identical publish is not double-recorded" do
    stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')

    publish("hello world")
    expect { publish("hello world") }.not_to change(Ai::PublishedPost, :count)
  end

  it "does not record anything for a write endpoint that does not opt in via captures_published_post" do
    plain_endpoint = create(:ai_data_source_endpoint, data_source: data_source, slug: "plain-write",
                             http_method: "POST", cache_ttl_seconds: 0, metadata: { "side_effecting" => true })
    stub_twitter(status: 201, body: '{"data":{"id":"999","text":"hello world"}}')

    tool = Ai::Tools::DataSourceTool.new(account: account, agent: agent, user: user)
    expect do
      tool.execute(params: {
        action: "data_source_query", data_source_id: "x-com",
        endpoint_id: plain_endpoint.id, params: { "text" => "hello world" }
      })
    end.not_to change(Ai::PublishedPost, :count)
  end

  it "does not record when the write is proposed (unauthorized) rather than dispatched" do
    # A separate account with NO manage-permission user — permission? checks
    # account-wide (any user in the account), so this must be a fresh account
    # rather than merely a different user on the shared `account` above.
    unauthorized_account = create(:account)
    # The FIRST user created in an account gets the owner role (all
    # permissions) — create the restricted user first (with an explicit
    # permissions: override) and hand it to the agent as :creator, so the
    # agent's factory does not implicitly create a second (would-be member,
    # but here still-first-if-created-earlier) user that could confuse the
    # account-wide grant.
    unauthorized_user = create(:user, account: unauthorized_account, permissions: ["ai.data_sources.query"])
    unauthorized_agent = create(:ai_agent, account: unauthorized_account, creator: unauthorized_user)
    unauthorized_source = Ai::DataSources::TemplateLibrary.install("x-com", account: unauthorized_account)[:data_source]

    tool = Ai::Tools::DataSourceTool.new(account: unauthorized_account, agent: unauthorized_agent, user: unauthorized_user)
    expect(Ai::DataSources::QueryService).not_to receive(:new)

    result = nil
    expect do
      result = tool.execute(params: {
        action: "data_source_query", data_source_id: unauthorized_source.id,
        endpoint_id: "create-post", params: { "text" => "hello world" }
      })
    end.not_to change(Ai::PublishedPost, :count)

    expect(result[:requires_approval]).to be(true)
  end
end
