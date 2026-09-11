# frozen_string_literal: true

require "rails_helper"

# E8 — the operator door for alert-channel configuration: write-only
# credentials, audited set/replace/clear, all-or-nothing validation, fail-closed
# on a store outage, and no path through MCP.
RSpec.describe "Api::V1::Platform::AlertChannels", type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:path) { "/api/v1/platform/alert_channels" }
  let(:slack_url) { "https://hooks.slack.com/services/T0/B0/planted-slack-credential" }
  let(:webhook_url) { "https://alerts.example.test/hook/planted-webhook-credential" }
  let(:token) { "planted-bearer-token-value" }
  let(:planted) { %w[planted-slack-credential planted-webhook-credential planted-bearer-token-value] }

  before { AdminSetting.where(key: Security::SecretStore::SETTING_KEY).delete_all }

  def data
    JSON.parse(response.body)["data"]
  end

  def audit_rows(action)
    AuditLog.where(action: action)
  end

  # Joins Rails' broadcast logger, so request parameters are captured too.
  def capturing_logs
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  describe "the gate" do
    it "refuses a user without settings.manage" do
      get path, headers: auth_headers_for(regular_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "admits an admin" do
      get path, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET — write-only" do
    it "answers configured flags, stored settings, defaults and severities, and never a value" do
      Monitoring::AlertChannels.write_secret!("slack_webhook_url", slack_url)

      get path, headers: headers, as: :json

      expect(data["secrets"]).to eq(
        "slack_webhook_url" => { "configured" => true },
        "webhook_url" => { "configured" => false },
        "webhook_auth_token" => { "configured" => false }
      )
      expect(data["settings"]).to eq("email" => nil, "min_severity_slack" => nil,
                                     "min_severity_email" => nil, "min_severity_webhook" => nil)
      expect(data["defaults"]).to eq("min_severity_slack" => "warning", "min_severity_email" => "error",
                                     "min_severity_webhook" => "critical")
      expect(response.body).not_to include("planted-slack-credential")
    end
  end

  describe "PATCH" do
    it "sets a credential, answers configured: true, and audits it by key name and actor" do
      patch path, params: { secrets: { slack_webhook_url: slack_url } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(data["secrets"]["slack_webhook_url"]).to eq("configured" => true)
      row = audit_rows("platform.alert_channels.secret_set").sole
      expect(row.resource_type).to eq("Monitoring::AlertChannels::AuditRef")
      expect(row.resource_id).to eq("slack_webhook_url")
      expect(row.user_id).to eq(admin_user.id)
    end

    it "audits a second write to the same key as a replace" do
      patch path, params: { secrets: { slack_webhook_url: slack_url } }, headers: headers, as: :json
      patch path, params: { secrets: { slack_webhook_url: "#{slack_url}-2" } }, headers: headers, as: :json

      expect(audit_rows("platform.alert_channels.secret_set").count).to eq(1)
      expect(audit_rows("platform.alert_channels.secret_replaced").count).to eq(1)
    end

    it "rejects a blank credential rather than reading it as a clear" do
      Monitoring::AlertChannels.write_secret!("slack_webhook_url", slack_url)

      patch path, params: { secrets: { slack_webhook_url: "" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Monitoring::AlertChannels.secret_configured?("slack_webhook_url")).to be(true)
    end

    it "rejects an unknown credential name instead of silently dropping it" do
      patch path, params: { secrets: { slack_webhook_uri: slack_url } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is all-or-nothing: an invalid address writes neither it nor the credential beside it" do
      patch path, params: { secrets: { slack_webhook_url: slack_url }, settings: { email: "not-an-address" } },
                  headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Monitoring::AlertChannels.secret_configured?("slack_webhook_url")).to be(false)
      expect(Monitoring::AlertChannels.email).to be_nil
      expect(AuditLog.where("action LIKE ?", "platform.alert_channels.%")).to be_empty
    end

    it "records which plain settings changed, never their values, and keeps the rows private" do
      patch path, params: { settings: { email: "ops-planted@example.com", min_severity_slack: "error" } },
                  headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      row = audit_rows("platform.alert_channels.settings_updated").sole
      expect(row.metadata["changed"]).to contain_exactly("email", "min_severity_slack")
      expect(row.attributes.to_json).not_to include("ops-planted@example.com")
      expect(SiteSetting.where("key LIKE ?", "platform.status.%").where(is_public: true)).to be_empty
    end
  end

  describe "DELETE secrets/:secret_key" do
    it "clears the credential and audits the clear" do
      Monitoring::AlertChannels.write_secret!("webhook_auth_token", token)

      delete "#{path}/secrets/webhook_auth_token", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(data["secrets"]["webhook_auth_token"]).to eq("configured" => false)
      expect(audit_rows("platform.alert_channels.secret_cleared").sole.metadata["had_value"]).to be(true)
    end

    it "audits a clear even when there was nothing to clear" do
      delete "#{path}/secrets/webhook_auth_token", headers: headers, as: :json

      expect(audit_rows("platform.alert_channels.secret_cleared").sole.metadata["had_value"]).to be(false)
    end

    it "rejects a key it does not own" do
      delete "#{path}/secrets/smtp_password", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the credential store is selected but unreachable" do
    before do
      AdminSetting.set(Security::SecretStore::SETTING_KEY, "vault")
      allow(Security::SecretStore::VaultBackend).to receive(:reachable?).and_return(false)
    end

    it "answers 503 on a read" do
      get path, headers: headers, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body).to_s).to include("secret_store_unavailable")
    end

    it "answers 503 on a write and writes nothing, not even the plain setting in the same request" do
      patch path, params: { secrets: { slack_webhook_url: slack_url }, settings: { email: "ops@example.com" } },
                  headers: headers, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(Monitoring::AlertChannels.email).to be_nil
    end
  end

  # PLANT AND GREP — the lead's oracle. Every credential goes in, is replaced,
  # read back and cleared; none may appear in any response body, any audit
  # row, or any log line, request parameters included.
  it "never lets a planted credential reach a response, an audit row or a log line" do
    bodies = []
    logs = capturing_logs do
      patch path, params: { secrets: { slack_webhook_url: slack_url, webhook_url: webhook_url,
                                       webhook_auth_token: token } }, headers: headers, as: :json
      bodies << response.body
      patch path, params: { secrets: { slack_webhook_url: "#{slack_url}-replaced" } }, headers: headers, as: :json
      bodies << response.body
      get path, headers: headers, as: :json
      bodies << response.body
      delete "#{path}/secrets/webhook_auth_token", headers: headers, as: :json
      bodies << response.body
    end

    expect(bodies.size).to eq(4)
    expect(Monitoring::AlertChannels.secret_configured?("slack_webhook_url")).to be(true)
    audit_json = AuditLog.all.map(&:attributes).to_json
    planted.each do |needle|
      expect(bodies.join).not_to include(needle)
      expect(audit_json).not_to include(needle)
      expect(logs).not_to include(needle)
    end
  end

  # The request log is the other place a credential can land. Keys nested
  # under `secrets` are filtered by the pre-existing :secret filter, so the
  # example above cannot tell whether :webhook_url is filtered at all. This one
  # sends the URL keys at the TOP level, where only :webhook_url can catch them.
  it "keeps a webhook URL out of the request log even when it arrives un-nested" do
    logs = capturing_logs do
      patch path, params: { slack_webhook_url: slack_url, webhook_url: webhook_url }, headers: headers, as: :json
    end

    expect(logs).to include("Parameters")
    expect(logs).not_to include("planted-slack-credential")
    expect(logs).not_to include("planted-webhook-credential")
  end

  # "Secrets never travel through MCP." No MCP tool may reach this config.
  it "is reachable from no MCP tool" do
    tool_sources = Dir[Rails.root.join("app/services/ai/tools/**/*.rb"),
                       Rails.root.join("app/services/mcp/**/*.rb")].map { |f| File.read(f) }

    expect(tool_sources.size).to be > 20
    expect(tool_sources.grep(/AlertChannels|alert_channels/)).to be_empty
  end
end
