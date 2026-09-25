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

  describe ".redis_config / .update_redis_config! (fc-38 decision #3 — password is encrypted, never in the blob)" do
    # fc-38 review item #4: unlike email's decrypt_secret (which falls back
    # to treating undecryptable ciphertext as the LITERAL credential, for
    # pre-encryption legacy rows only email ever had), redis/vault have no
    # such legacy plaintext-in-an-_encrypted-key case — a decrypt failure
    # here can only mean real corruption or a key-rotation gap, and the
    # ciphertext itself must never be handed anywhere as if it were the
    # actual password.
    # round 3 review item #2 (LOW): a decrypt failure used to merge
    # "password" => nil straight over ENV["REDIS_PASSWORD"]'s default,
    # sending the actual Redis connection out UNAUTHENTICATED instead of
    # with whatever credential was configured before the corruption. A
    # decrypt failure must fall back to the blob's own password (ENV or the
    # default), never nil — never the ciphertext either.
    it "falls back to the blob's own password (e.g. the ENV default), never nil, when the stored value fails to decrypt" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-fallback-password")
      AdminSetting.create!(key: "redis_config_password_encrypted", value: "not-valid-ciphertext")
      expect(Rails.logger).to receive(:error) do |message|
        expect(message).to include("redis_config_password")
        expect(message).to include("DecryptionError")
        expect(message).not_to include("not-valid-ciphertext")
      end

      expect(described_class.redis_config["password"]).to eq("env-fallback-password")
    end

    it "falls back to the non-secret blob's own password (e.g. the ENV default) when no encrypted row exists yet" do
      config = described_class.redis_config

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
      expect(config["password"]).to eq(AdminSetting.redis_config["password"])
    end

    it "update_redis_config! with no password key present leaves the encrypted row untouched (masked-resubmission skip)" do
      password = "redis-unit-#{SecureRandom.hex(4)}"
      described_class.update_redis_config!("password" => password, "host" => "127.0.0.1")
      before_value = AdminSetting.find_by(key: "redis_config_password_encrypted").value

      described_class.update_redis_config!("host" => "192.168.1.1")

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted").value).to eq(before_value)
      expect(described_class.redis_config["password"]).to eq(password)
      expect(AdminSetting.redis_config["host"]).to eq("192.168.1.1")
    end

    it "update_redis_config! never writes 'password' into the non-secret AdminSetting.redis_config blob" do
      described_class.update_redis_config!("password" => "redis-unit-blob-check", "host" => "127.0.0.1")

      expect(AdminSetting.find_by(key: "redis_config").value).not_to include("redis-unit-blob-check")
    end

    # fc-38 review item #3(b): AdminSetting.update_redis_config's own
    # `current_config = redis_config` deep-merges default_redis_config —
    # which carries ENV["REDIS_PASSWORD"] as its default "password" — into
    # whatever gets saved. A save that never even mentions "password" (e.g.
    # changing only "host") would silently bake the current ENV redis
    # password into the blob as plaintext, defeating the encryption above
    # for any deployment that sets REDIS_PASSWORD.
    it "never writes a password key into the blob at all, even when ENV['REDIS_PASSWORD'] is set and the save omits password" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("REDIS_PASSWORD", nil).and_return("env-redis-password-should-never-be-in-blob")

      described_class.update_redis_config!("host" => "127.0.0.1")

      blob = AdminSetting.find_by(key: "redis_config").value
      expect(JSON.parse(blob)).not_to have_key("password")
    end
  end

  describe ".vault_config / .update_vault_config! (fc-38 decision #3 — role_id/secret_id are encrypted, never in the blob)" do
    it "returns empty-string role_id/secret_id and nil vault_addr when nothing is configured" do
      config = described_class.vault_config

      expect(config).to eq("vault_addr" => nil, "vault_role_id" => "", "vault_secret_id" => "")
    end

    # fc-38 review item #2: before the data migration runs (or for any row
    # written before this hardening shipped), the blob may still hold a
    # plaintext vault_role_id/vault_secret_id with no _encrypted row yet.
    # .redis_config already falls back to the blob's own value in that case;
    # .vault_config must do the same, or Vault authentication (and the admin
    # UI) would silently see blank credentials until the migration runs.
    it "falls back to the blob's plaintext vault_role_id/vault_secret_id when no encrypted row exists yet" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "pre-migration-role", "vault_secret_id" => "pre-migration-secret" }.to_json
      )

      config = described_class.vault_config

      expect(AdminSetting.exists?(key: "vault_role_id_encrypted")).to be(false)
      expect(config["vault_role_id"]).to eq("pre-migration-role")
      expect(config["vault_secret_id"]).to eq("pre-migration-secret")
    end

    it "prefers the encrypted row over the blob's plaintext once one exists" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "stale-plaintext-role" }.to_json
      )
      described_class.update_vault_config!("vault_role_id" => "fresh-encrypted-role")

      expect(described_class.vault_config["vault_role_id"]).to eq("fresh-encrypted-role")
    end

    it "update_vault_config! writes only the keys present, leaving the others untouched" do
      described_class.update_vault_config!("vault_addr" => "http://vault.example.internal:8200", "vault_role_id" => "role-a")
      described_class.update_vault_config!("vault_secret_id" => "secret-b")

      config = described_class.vault_config
      expect(config["vault_addr"]).to eq("http://vault.example.internal:8200")
      expect(config["vault_role_id"]).to eq("role-a")
      expect(config["vault_secret_id"]).to eq("secret-b")
    end

    it "never writes vault_role_id/vault_secret_id into the vault_config blob" do
      described_class.update_vault_config!("vault_role_id" => "role-blob-check", "vault_secret_id" => "secret-blob-check")

      expect(AdminSetting.find_by(key: "vault_config")&.value.to_s).not_to include("role-blob-check")
      expect(AdminSetting.find_by(key: "vault_config")&.value.to_s).not_to include("secret-blob-check")
    end

    # fc-38 review item #3(b): update_vault_config! reads raw_vault_blob and
    # merges "vault_addr" into it — if the blob already carries a stale
    # vault_role_id/vault_secret_id (a leftover from before this hardening,
    # or a row the migration hasn't reached yet), a vault_addr-only save
    # would round-trip that stale value straight back into the blob via the
    # merge, keeping the plaintext alive indefinitely.
    it "strips a pre-existing plaintext vault_role_id/vault_secret_id from the blob on a vault_addr-only save" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "stale-plaintext-role", "vault_secret_id" => "stale-plaintext-secret" }.to_json
      )

      described_class.update_vault_config!("vault_addr" => "http://vault.updated.internal:8200")

      blob = JSON.parse(AdminSetting.find_by(key: "vault_config").value)
      expect(blob).to eq("vault_addr" => "http://vault.updated.internal:8200")
    end

    # round 3 review item #1 (MEDIUM): the strip-on-write helper used to just
    # delete a plaintext field from the blob once it was present — it never
    # checked whether an _encrypted row existed FIRST. A host-only (or
    # addr-only) save on a row from before the encryption migration ran
    # stripped the plaintext straight into the void: no encrypted row ever
    # got created, so the credential was gone, not migrated.
    it "encrypts a pre-migration plaintext redis password into its own row before stripping it, on a host-only save" do
      AdminSetting.create!(
        key: "redis_config",
        value: { "host" => "127.0.0.1", "port" => 6379, "password" => "pre-migration-redis-password" }.to_json
      )

      described_class.update_redis_config!("host" => "192.168.1.1")

      encrypted = AdminSetting.find_by(key: "redis_config_password_encrypted")
      expect(encrypted).not_to be_nil
      expect(encrypted.value).not_to include("pre-migration-redis-password")
      expect(described_class.redis_config["password"]).to eq("pre-migration-redis-password")
      expect(AdminSetting.find_by(key: "redis_config").value).not_to include("pre-migration-redis-password")
    end

    it "encrypts pre-migration plaintext vault_role_id/vault_secret_id into their own rows before stripping them, on a vault_addr-only save" do
      AdminSetting.create!(
        key: "vault_config",
        value: { "vault_addr" => "http://vault.internal:8200", "vault_role_id" => "pre-migration-role", "vault_secret_id" => "pre-migration-secret" }.to_json
      )

      described_class.update_vault_config!("vault_addr" => "http://vault.updated.internal:8200")

      expect(AdminSetting.find_by(key: "vault_role_id_encrypted")).not_to be_nil
      expect(AdminSetting.find_by(key: "vault_secret_id_encrypted")).not_to be_nil
      config = described_class.vault_config
      expect(config["vault_role_id"]).to eq("pre-migration-role")
      expect(config["vault_secret_id"]).to eq("pre-migration-secret")
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
