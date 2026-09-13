# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment E1 — outbound webhooks, read-only.
#
# `webhook_endpoints` carries FOUR secret-bearing fields, two of them PLAINTEXT
# columns (`secret_key`, `signature_secret`) and two jsonb header bags that
# routinely hold an Authorization token. The REST twin already returns
# `secret_key` verbatim in its show payload, so "the model does not expose it"
# is not an argument available here. Every secret oracle below plants a real
# value and greps the serialized response for that exact string.
RSpec.describe Ai::Tools::WebhookReadTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:first_user) { create(:user, account: account) }

  def actor(*permissions)
    described_class.new(account: account, user: create(:user, account: account, permissions: permissions))
  end

  let(:tool) { actor("webhook.read") }

  def advertised_actions = %w[list_webhooks get_webhook list_webhook_deliveries]

  def endpoint(**attrs)
    create(:webhook_endpoint, **{ account: account }.merge(attrs))
  end

  describe "declarations" do
    it "declares every advertised action, all read-only" do
      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, klass| klass == described_class.name }
                                                       .keys.map(&:to_s)
      expect(advertised).to match_array(advertised_actions)

      advertised.each do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).not_to be_nil, "#{action} is advertised but not declared"
        expect(declaration[:mutating]).to be(false)
      end
    end

    it "carries readOnlyHint on the wire for every verb" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      advertised_actions.each do |action|
        expect(entries["platform.#{action}"]).not_to be_nil
        expect(entries["platform.#{action}"]["annotations"]).to include("readOnlyHint" => true)
      end
    end

    it "floors on webhook.read, the name the REST controller checks" do
      expect(::Permissions.permission_exists?("webhook.read")).to be true
      expect(described_class::ACTION_PERMISSIONS.values.uniq).to eq([ "webhook.read" ])
      expect(described_class::ACTION_PERMISSIONS.keys).to match_array(advertised_actions)
    end
  end

  describe "permission enforcement" do
    it "refuses every verb without webhook.read, and allows every verb with it" do
      row = endpoint
      calls = [
        { action: "list_webhooks" },
        { action: "get_webhook", id: row.id },
        { action: "list_webhook_deliveries" }
      ]

      stranger = actor
      calls.each do |params|
        result = stranger.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} was allowed without the permission"
        expect(result[:error]).to include("webhook.read")
        expect(result[:data]).to be_nil
      end

      calls.each do |params|
        expect(tool.execute(params: params)[:success]).to be(true), "#{params[:action]} was refused for a holder"
      end
    end
  end

  describe "account isolation" do
    it "lists only this account's endpoints and reports another's as absent" do
      mine = endpoint(url: "https://mine.example.test/hook")
      theirs = create(:webhook_endpoint, account: other_account, url: "https://theirs.example.test/hook")

      listed = tool.execute(params: { action: "list_webhooks" })
      expect(listed.dig(:data, :webhooks).map { |w| w[:id] }).to eq([ mine.id ])
      expect(listed.to_json).not_to include("theirs.example.test")

      expect(tool.execute(params: { action: "get_webhook", id: theirs.id })[:success]).to be false
    end

    it "never returns another account's deliveries" do
      theirs = create(:webhook_endpoint, account: other_account)
      foreign_delivery = create(:webhook_delivery, :failed, webhook_endpoint: theirs)
      mine = create(:webhook_delivery, :successful, webhook_endpoint: endpoint)

      ids = tool.execute(params: { action: "list_webhook_deliveries" })
                .dig(:data, :deliveries).map { |d| d[:id] }
      expect(ids).to eq([ mine.id ])
      expect(ids).not_to include(foreign_delivery.id)
    end
  end

  describe "list_webhooks" do
    it "filters by active_only and by event type, both arms" do
      active = endpoint(is_active: true, event_types: [ "user.created" ])
      inactive = endpoint(is_active: false, event_types: [ "payment.succeeded" ])

      only_active = tool.execute(params: { action: "list_webhooks", active_only: true })
                        .dig(:data, :webhooks).map { |w| w[:id] }
      expect(only_active).to include(active.id)
      expect(only_active).not_to include(inactive.id)

      by_event = tool.execute(params: { action: "list_webhooks", event_type: "payment.succeeded" })
                     .dig(:data, :webhooks).map { |w| w[:id] }
      expect(by_event).to eq([ inactive.id ])
      expect(by_event).not_to include(active.id)
    end

    it "reports circuit-breaker state and delivery counters" do
      row = endpoint(consecutive_failures: 4, failure_count: 9, success_count: 100,
                     circuit_broken_at: 5.minutes.ago, circuit_cooldown_until: 10.minutes.from_now)

      listed = tool.execute(params: { action: "list_webhooks" }).dig(:data, :webhooks).first
      expect(listed).to include(id: row.id, consecutive_failures: 4, failure_count: 9,
                                success_count: 100, circuit_broken: true)
      expect(listed[:circuit_cooldown_until]).to be_present
    end
  end

  describe "get_webhook" do
    it "adds delivery configuration the list omits" do
      row = endpoint(timeout_seconds: 45, max_retries: 7, retry_backoff: "linear")

      detail = tool.execute(params: { action: "get_webhook", id: row.id }).dig(:data, :webhook)
      expect(detail).to include(timeout_seconds: 45, max_retries: 7, retry_backoff: "linear")

      listed = tool.execute(params: { action: "list_webhooks" }).dig(:data, :webhooks).first
      expect(listed).not_to have_key(:timeout_seconds)
    end
  end

  describe "list_webhook_deliveries" do
    it "filters by endpoint, status and failed_only, both arms" do
      a = endpoint
      b = endpoint
      ok = create(:webhook_delivery, :successful, webhook_endpoint: a)
      bad = create(:webhook_delivery, :failed, webhook_endpoint: b)

      by_endpoint = tool.execute(params: { action: "list_webhook_deliveries", webhook_id: a.id })
                        .dig(:data, :deliveries).map { |d| d[:id] }
      expect(by_endpoint).to eq([ ok.id ])
      expect(by_endpoint).not_to include(bad.id)

      failed = tool.execute(params: { action: "list_webhook_deliveries", failed_only: true })
                   .dig(:data, :deliveries).map { |d| d[:id] }
      expect(failed).to include(bad.id)
      expect(failed).not_to include(ok.id)

      by_status = tool.execute(params: { action: "list_webhook_deliveries", status: "success" })
                      .dig(:data, :deliveries).map { |d| d[:id] }
      expect(by_status).to eq([ ok.id ])
    end

    it "returns the diagnostic fields an operator needs" do
      row = endpoint
      create(:webhook_delivery, :failed, webhook_endpoint: row,
                                         response_status: 503, response_time_ms: 1200,
                                         error_message: "upstream timeout")

      delivery = tool.execute(params: { action: "list_webhook_deliveries" }).dig(:data, :deliveries).first
      expect(delivery).to include(response_status: 503, response_time_ms: 1200,
                                  error_message: "upstream timeout", attempt_number: 2)
    end
  end

  # THE ONES THAT MATTER. Plant real values, then grep.
  describe "secret material" do
    let(:shared_secret) { "whsec_#{SecureRandom.hex(24)}" }
    let(:signing_secret) { "sig_#{SecureRandom.hex(24)}" }
    let(:bearer) { "Bearer tok_#{SecureRandom.hex(16)}" }
    let!(:row) do
      endpoint(secret_key: shared_secret, signature_secret: signing_secret,
               custom_headers: { "Authorization" => bearer }, headers: { "X-Api-Key" => bearer })
    end

    it "stores every planted value (so these oracles are not vacuous)" do
      row.reload
      expect(row.secret_key).to eq(shared_secret)
      expect(row.signature_secret).to eq(signing_secret)
      expect(row.custom_headers["Authorization"]).to eq(bearer)
    end

    it "emits neither secret nor a MASK of it, on either endpoint verb" do
      bodies = [
        tool.execute(params: { action: "list_webhooks" }).to_json,
        tool.execute(params: { action: "get_webhook", id: row.id }).to_json
      ]

      bodies.each do |body|
        expect(body).not_to include(shared_secret)
        expect(body).not_to include(signing_secret)
        expect(body).not_to include(bearer)
        # A mask still discloses length and shape, so the tool reports a
        # BOOLEAN. These key names must be absent entirely.
        %w[secret_key signature_secret custom_headers masked_secret].each do |forbidden|
          expect(body).not_to include(forbidden), "#{forbidden} appears in a webhook response"
        end
      end
    end

    it "still SAYS whether a secret is configured, both arms" do
      configured = tool.execute(params: { action: "get_webhook", id: row.id }).dig(:data, :webhook)
      expect(configured).to include(secret_configured: true, signature_configured: true)

      # WebhookEndpoint MINTS a secret_key on create
      # (generate_secret_token_value), so passing nil at create is overwritten.
      # Clear the columns after the fact to reach the genuinely-unconfigured
      # state — without this the "false" arm is unreachable and the assertion
      # above would be the only one that ever runs.
      bare = endpoint
      bare.update_columns(secret_key: nil, signature_secret: nil)
      status = tool.execute(params: { action: "get_webhook", id: bare.id }).dig(:data, :webhook)
      expect(status).to include(secret_configured: false, signature_configured: false)
    end

    it "never emits a delivery's request headers or raw response body" do
      planted_signature = "sha256=#{SecureRandom.hex(32)}"
      planted_body = "SECRET-RESPONSE-#{SecureRandom.hex(12)}"
      create(:webhook_delivery, :failed, webhook_endpoint: row,
                                         request_headers: { "X-Signature" => planted_signature, "Authorization" => bearer },
                                         response_headers: { "X-Upstream-Token" => bearer },
                                         response_body: planted_body)

      body = tool.execute(params: { action: "list_webhook_deliveries" }).to_json

      expect(body).not_to include(planted_signature)
      expect(body).not_to include(planted_body)
      expect(body).not_to include(bearer)
      %w[request_headers response_headers response_body].each do |forbidden|
        expect(body).not_to include(forbidden), "#{forbidden} appears in a delivery response"
      end
    end
  end

  it "refuses an action it does not advertise" do
    expect(tool.execute(params: { action: "delete_webhook" })[:success]).to be false
  end
end
