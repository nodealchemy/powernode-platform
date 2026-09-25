# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SystemSettings do
  describe ".general_settings" do
    it "reads the flat general keys admin_settings_controller writes, nil when unset" do
      AdminSetting.find_or_create_by(key: "system_name") { |s| s.value = "Powernode" }

      settings = described_class.general_settings

      expect(settings["system_name"]).to eq("Powernode")
      expect(settings["registration_enabled"]).to be_nil
    end
  end

  describe ".update_general_settings!" do
    it "writes flat keys as their string value" do
      updated = described_class.update_general_settings!("registration_enabled" => false)

      expect(updated).to eq("registration_enabled" => false)
      expect(AdminSetting.find_by(key: "registration_enabled").value).to eq("false")
    end

    it "fans a Hash value out into dotted sub-keys, mirroring the pre-move controller writer" do
      updated = described_class.update_general_settings!(
        "system_notifications" => { "email_enabled" => true, "sms_enabled" => false }
      )

      expect(updated).to eq(
        "system_notifications.email_enabled" => true,
        "system_notifications.sms_enabled" => false
      )
      expect(AdminSetting.find_by(key: "system_notifications.email_enabled").value).to eq("true")
      expect(AdminSetting.find_by(key: "system_notifications.sms_enabled").value).to eq("false")
    end
  end

  describe ".registration_enabled? / .email_verification_required?" do
    # Pins the exact string->bool mapping config_controller.rb used before
    # this method moved here, so an operator's existing stored value keeps
    # meaning the same thing.
    {
      "true" => true, "1" => true, "yes" => true, "on" => true, "enabled" => true,
      "false" => false, "0" => false, "no" => false, "off" => false, "disabled" => false,
      "TRUE" => true, "  true  " => true,
      "garbage" => true, "" => true
    }.each do |stored, expected|
      it "reads #{stored.inspect} as #{expected}" do
        AdminSetting.find_or_create_by(key: "registration_enabled") { |s| s.value = stored }

        expect(described_class.registration_enabled?).to eq(expected)
      end
    end

    it "defaults to true (registration) / true (email verification) when the row does not exist" do
      expect(described_class.registration_enabled?).to be(true)
      expect(described_class.email_verification_required?).to be(true)
    end

    it "defaults to true when the lookup raises" do
      allow(AdminSetting).to receive(:find_by).and_raise(StandardError, "db down")

      expect(described_class.registration_enabled?).to be(true)
    end
  end

  describe ".email_settings / .update_email_settings!" do
    it "round-trips a plain (non-secret) field" do
      described_class.update_email_settings!("smtp_host" => "smtp.example.com")

      expect(described_class.email_settings[:smtp_host]).to eq("smtp.example.com")
    end

    it "normalizes the 'provider' param key to email_provider, like the pre-move controller" do
      described_class.update_email_settings!("provider" => "sendgrid")

      expect(AdminSetting.find_by(key: "email_provider").value).to eq("sendgrid")
      expect(described_class.email_settings[:provider]).to eq("sendgrid")
    end

    it "encrypts a _password/_api_key/_secret_key suffixed value via CredentialEncryptionService and decrypts it back on read" do
      described_class.update_email_settings!("smtp_password" => "hunter2")

      raw = AdminSetting.find_by(key: "smtp_password_encrypted").value
      expect(raw).not_to include("hunter2")
      expect(described_class.email_settings[:smtp_password]).to eq("hunter2")
    end

    it "returns empty string for an unset secret rather than nil" do
      expect(described_class.email_settings[:sendgrid_api_key]).to eq("")
    end

    it "treats a pre-encryption plaintext value as its literal (backward compatibility), same as the pre-move controller" do
      AdminSetting.set("smtp_password_encrypted", "plaintext-legacy-value")

      expect(described_class.email_settings[:smtp_password]).to eq("plaintext-legacy-value")
    end
  end

  describe "proxy delegation (thin passthrough to the ServiceConfiguration concern already on AdminSetting)" do
    it "delegates .proxy_url_config" do
      expect(AdminSetting).to receive(:reverse_proxy_url_config).and_return(enabled: true)

      expect(described_class.proxy_url_config).to eq(enabled: true)
    end

    it "delegates .update_proxy_url_config!" do
      expect(AdminSetting).to receive(:update_reverse_proxy_url_config).with({ enabled: true }).and_return(enabled: true)

      expect(described_class.update_proxy_url_config!({ enabled: true })).to eq(enabled: true)
    end

    it "delegates .validate_proxy_host" do
      expect(AdminSetting).to receive(:validate_proxy_host).with("example.com").and_return(valid: true)

      expect(described_class.validate_proxy_host("example.com")).to eq(valid: true)
    end

    it "delegates .generate_api_url" do
      expect(AdminSetting).to receive(:generate_api_url).with({ forwarded_host: "example.com" }).and_return(base_url: "https://example.com")

      expect(described_class.generate_api_url({ forwarded_host: "example.com" })).to eq(base_url: "https://example.com")
    end

    it "delegates .add_trusted_host" do
      expect(AdminSetting).to receive(:add_trusted_host).with("*.example.com").and_return(true)

      expect(described_class.add_trusted_host("*.example.com")).to be(true)
    end

    it "delegates .remove_trusted_host" do
      expect(AdminSetting).to receive(:remove_trusted_host).with("*.example.com").and_return(true)

      expect(described_class.remove_trusted_host("*.example.com")).to be(true)
    end

    it "delegates .test_proxy_headers" do
      headers = { "X-Forwarded-Host" => "example.com" }
      expect(AdminSetting).to receive(:test_proxy_headers).with(headers).and_return(proxy_context: {})

      expect(described_class.test_proxy_headers(headers)).to eq(proxy_context: {})
    end
  end
end
