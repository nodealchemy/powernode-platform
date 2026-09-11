# frozen_string_literal: true

require "rails_helper"

# E8 — AlertingService reads its channels from Monitoring::AlertChannels:
# no ENV, no master switch, credentials read at the point of use, errors
# logged by class, and a credential store outage failing CLOSED and VISIBLY.
RSpec.describe Monitoring::AlertingService, "channel configuration" do
  subject(:service) { described_class.new }

  let(:slack_url) { "https://hooks.slack.com/services/T0/B0/planted-slack-credential" }
  let(:webhook_url) { "https://alerts.example.test/hook/planted-webhook-credential" }
  let(:webhook_token) { "planted-bearer-token-value" }

  before { AdminSetting.where(key: Security::SecretStore::SETTING_KEY).delete_all }

  def configure_slack(url = slack_url)
    Monitoring::AlertChannels.write_secret!("slack_webhook_url", url)
  end

  # Captures EVERYTHING the application logs during the block, request
  # parameters included, by joining Rails' broadcast logger.
  def capturing_logs
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  it "with nothing configured, delivers nowhere and POSTs nothing" do
    expect(service.send_alert(title: "t", message: "m", severity: :critical)).to eq({})
    expect(a_request(:post, /.*/)).not_to have_been_made
  end

  it "delivers to Slack at or above the default floor, without a channel override" do
    configure_slack
    stub = stub_request(:post, slack_url).to_return(status: 200)

    result = service.send_alert(title: "t", message: "m", severity: :warning)

    expect(result["slack"]).to eq(success: true)
    expect(stub).to have_been_requested.once
    expect(a_request(:post, slack_url).with { |req| !JSON.parse(req.body).key?("channel") }).to have_been_made
  end

  it "does not deliver below the floor" do
    configure_slack

    service.send_alert(title: "t", message: "m", severity: :info)

    expect(a_request(:post, /.*/)).not_to have_been_made
  end

  it "reads the floor from its SiteSetting" do
    configure_slack
    Monitoring::AlertChannels.update_settings!("min_severity_slack" => "critical")

    service.send_alert(title: "t", message: "m", severity: :error)

    expect(a_request(:post, /.*/)).not_to have_been_made
  end

  it "sends the webhook token as a bearer header" do
    Monitoring::AlertChannels.write_secret!("webhook_url", webhook_url)
    Monitoring::AlertChannels.write_secret!("webhook_auth_token", webhook_token)
    stub_request(:post, webhook_url).to_return(status: 200)

    service.send_alert(title: "t", message: "m", severity: :critical)

    expect(a_request(:post, webhook_url).with(headers: { "Authorization" => "Bearer #{webhook_token}" }))
      .to have_been_made.once
  end

  describe "the credential store is selected but unreachable" do
    before do
      Monitoring::AlertChannels.update_settings!("email" => "ops@example.com")
      AdminSetting.set(Security::SecretStore::SETTING_KEY, "vault")
      allow(Security::SecretStore::VaultBackend).to receive(:reachable?).and_return(false)
      allow(WorkerJobService).to receive(:enqueue_alert_email).and_return({ "status" => "queued" })
    end

    it "fails closed and records the reason instead of skipping silently" do
      logs = capturing_logs { @result = service.send_alert(title: "t", message: "m", severity: :critical) }

      expect(@result["slack"]).to eq(success: false, error: described_class::STORE_UNAVAILABLE)
      expect(@result["webhook"]).to eq(success: false, error: described_class::STORE_UNAVAILABLE)
      expect(logs).to include("not delivered: #{described_class::STORE_UNAVAILABLE}")
      expect(a_request(:post, /.*/)).not_to have_been_made
    end

    it "still delivers the channel that needs no credential" do
      result = service.send_alert(title: "t", message: "m", severity: :critical)

      expect(result["email"]).to include(success: true)
    end
  end

  # PLANT AND GREP. A malformed stored URL makes URI raise with the URL
  # verbatim in its message; the service must log the error CLASS only.
  # Planted straight into the store, past validation, because that is how a
  # malformed value would arrive: an older write, or a restore.
  it "never writes a credential into the log or the result when delivery fails" do
    malformed = "https://hooks.slack.com/services/planted credential with spaces"
    Security::SecretStore.write(account: nil, scope: Monitoring::AlertChannels::SECRET_SCOPE,
                                key: "slack_webhook_url", value: malformed)

    logs = capturing_logs { @result = service.send_alert(title: "t", message: "m", severity: :critical) }

    expect(@result["slack"]).to include(success: false, error: "delivery_failed")
    expect(logs).to include("slack delivery failed")
    expect(logs).not_to include("planted credential")
    expect(@result.to_s).not_to include("planted credential")
  end

  it "holds no credential in the service object, where inspect would print it" do
    configure_slack

    expect(service.inspect).not_to include("planted-slack-credential")
  end
end
