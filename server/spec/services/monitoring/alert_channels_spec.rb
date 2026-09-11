# frozen_string_literal: true

require "rails_helper"

# E8 — alert-channel configuration: credentials in Security::SecretStore,
# plain settings as SiteSettings, absence-means-off, nothing public.
RSpec.describe Monitoring::AlertChannels do
  let(:slack_url) { "https://hooks.slack.com/services/T0/B0/planted-slack-credential" }

  before { AdminSetting.where(key: Security::SecretStore::SETTING_KEY).delete_all }

  describe "credentials" do
    it "reports :set on first write and :replaced on the second, storing the value in the SecretStore" do
      expect(described_class.write_secret!("slack_webhook_url", slack_url)).to eq(:set)
      expect(described_class.write_secret!("slack_webhook_url", "#{slack_url}-2")).to eq(:replaced)

      stored = Security::SecretStore.read(account: nil, scope: described_class::SECRET_SCOPE, key: "slack_webhook_url")
      expect(stored).to eq("#{slack_url}-2")
    end

    it "answers presence and never a value" do
      described_class.write_secret!("slack_webhook_url", slack_url)

      status = described_class.secrets_status
      expect(status["slack_webhook_url"]).to eq(configured: true)
      expect(status["webhook_url"]).to eq(configured: false)
      expect(status.to_s).not_to include(slack_url)
    end

    it "rejects a URL credential that is not https, without echoing it" do
      expect { described_class.write_secret!("webhook_url", "http://example.test/planted-http") }
        .to raise_error(described_class::InvalidSetting) { |e| expect(e.message).not_to include("planted-http") }
    end

    it "rejects a blank value: clearing is its own action" do
      expect { described_class.write_secret!("webhook_auth_token", "  ") }.to raise_error(described_class::InvalidSetting)
    end

    it "rejects a key it does not own" do
      expect { described_class.write_secret!("smtp_password", "x") }.to raise_error(described_class::InvalidSetting)
    end

    it "clears, and reports whether there was anything to clear" do
      described_class.write_secret!("webhook_auth_token", "planted-token")

      expect(described_class.clear_secret!("webhook_auth_token")).to be(true)
      expect(described_class.clear_secret!("webhook_auth_token")).to be(false)
      expect(described_class.secret_configured?("webhook_auth_token")).to be(false)
    end
  end

  describe "plain settings — absence means off" do
    it "seeds nothing: with no row the email channel is off and each floor is the named default" do
      expect(described_class.email).to be_nil
      expect(described_class.min_severity("slack")).to eq(:warning)
      expect(described_class.min_severity("email")).to eq(:error)
      expect(described_class.min_severity("webhook")).to eq(:critical)
    end

    it "writes validated values and reads them back" do
      described_class.update_settings!("email" => "ops@example.com", "min_severity_slack" => "error")

      expect(described_class.email).to eq("ops@example.com")
      expect(described_class.min_severity("slack")).to eq(:error)
    end

    it "is all-or-nothing: one invalid value writes none of the batch" do
      expect {
        described_class.update_settings!("email" => "ops@example.com", "min_severity_slack" => "loud")
      }.to raise_error(described_class::InvalidSetting)

      expect(described_class.email).to be_nil
    end

    it "rejects an address that is not one" do
      expect { described_class.update_settings!("email" => "not-an-address") }
        .to raise_error(described_class::InvalidSetting)
    end

    it "removes the row on a blank value rather than storing a blank" do
      described_class.update_settings!("email" => "ops@example.com")
      described_class.update_settings!("email" => "")

      expect(SiteSetting.exists?(key: described_class.setting_key("email"))).to be(false)
      expect(described_class.email).to be_nil
    end

    it "falls back to the default floor when a stored value is not a severity" do
      SiteSetting.set(described_class.setting_key("min_severity_email"), "loud", is_public: false)

      expect(described_class.min_severity("email")).to eq(:error)
    end
  end

  # The lead's ruling: no platform.status.* setting is ever public. The DB
  # column defaults to TRUE, so this example writes the careless way — create!
  # without naming is_public, as a later seed might — and requires the row to
  # come out private anyway.
  describe "no platform.status.* setting is public" do
    it "keeps a row private even when the writer forgets the flag" do
      row = SiteSetting.create!(key: "platform.status.alert_channels.email", value: "ops@example.com",
                                setting_type: "string")

      expect(row.reload.is_public).to be(false)
    end

    it "holds across every row the writer creates" do
      described_class.update_settings!("email" => "ops@example.com", "min_severity_slack" => "error",
                                       "min_severity_email" => "warning", "min_severity_webhook" => "error")

      expect(SiteSetting.where("key LIKE ?", "platform.status.%").where(is_public: true)).to be_empty
    end

    it "does not reach outside the namespace" do
      row = SiteSetting.create!(key: "site_name_e8_probe", value: "x", setting_type: "string")

      expect(row.reload.is_public).to be(true)
    end
  end
end
