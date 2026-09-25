# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260925040000_strip_env_captured_values_from_redis_config_blob.rb")

# fc-38 round 4 review (root-cause fix follow-up) — cleans up rows already
# polluted by the fixed ServiceConfiguration#update_redis_config bug: a
# blob "password"/"url" identical to the CURRENT ENV value, or an already-
# encrypted redis_config_password_encrypted row whose decrypted value
# matches CURRENT ENV["REDIS_PASSWORD"], is stripped/destroyed so it stops
# shadowing ENV. A value that does NOT match current ENV is left alone —
# it can't be told apart from a deliberately admin-stored value.
RSpec.describe StripEnvCapturedValuesFromRedisConfigBlob do
  subject(:migration) { described_class.new }

  # Same rationale as the sibling migration's spec: capture #say's messages
  # instead of letting them hit stdout, so the "never a value in the
  # message" requirement is directly assertable.
  let(:said_messages) { [] }

  before do
    allow(migration).to receive(:say) { |msg, *| said_messages << msg }
  end

  def seed_redis_config(**fields)
    AdminSetting.create!(key: "redis_config", value: { "host" => "127.0.0.1", "port" => 6379 }.merge(fields).to_json)
  end

  around do |example|
    original_password = ENV["REDIS_PASSWORD"]
    original_url = ENV["REDIS_URL"]
    example.run
  ensure
    ENV["REDIS_PASSWORD"] = original_password
    ENV["REDIS_URL"] = original_url
  end

  describe "#up" do
    it "strips a blob password identical to the current ENV value" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      seed_redis_config(password: "current-env-password")

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("password")
    end

    it "leaves a blob password that does NOT match current ENV alone (can't tell captured from deliberate)" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      seed_redis_config(password: "a-different-admin-typed-password")

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["password"]).to eq("a-different-admin-typed-password")
    end

    it "leaves a blob password alone when REDIS_PASSWORD is unset (nothing to compare against)" do
      ENV["REDIS_PASSWORD"] = nil
      seed_redis_config(password: "some-stored-password")

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["password"]).to eq("some-stored-password")
    end

    it "strips a blob url identical to the current raw ENV REDIS_URL" do
      ENV["REDIS_URL"] = "redis://:current-env-password@redis.internal:6379/0"
      seed_redis_config(url: "redis://:current-env-password@redis.internal:6379/0")

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("url")
    end

    it "strips a blob url matching the userinfo-stripped form of the current ENV REDIS_URL (the round 3 sanitizer regression shape)" do
      ENV["REDIS_URL"] = "redis://:current-env-password@redis.internal:6379/0"
      seed_redis_config(url: "redis://redis.internal:6379/0") # what the buggy sanitizer would have left behind

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob).not_to have_key("url")
    end

    it "leaves a blob url that does NOT match current ENV (raw or sanitized) alone" do
      ENV["REDIS_URL"] = "redis://:current-env-password@redis.internal:6379/0"
      seed_redis_config(url: "redis://a-genuinely-different-admin-host:6379/0")

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["url"]).to eq("redis://a-genuinely-different-admin-host:6379/0")
    end

    it "destroys an encrypted password row whose decrypted value matches current ENV['REDIS_PASSWORD']" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      AdminSetting.create!(
        key: "redis_config_password_encrypted",
        value: Security::CredentialEncryptionService.encrypt_value("current-env-password")
      )

      migration.up

      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).to be_nil
    end

    it "leaves an encrypted password row whose decrypted value does NOT match current ENV alone" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      AdminSetting.create!(
        key: "redis_config_password_encrypted",
        value: Security::CredentialEncryptionService.encrypt_value("a-genuinely-different-admin-password")
      )

      migration.up

      row = AdminSetting.find_by(key: "redis_config_password_encrypted")
      expect(row).not_to be_nil
      expect(Security::CredentialEncryptionService.decrypt_value(row.value)).to eq("a-genuinely-different-admin-password")
    end

    it "leaves an undecryptable encrypted password row alone rather than raising" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      AdminSetting.create!(key: "redis_config_password_encrypted", value: "not-valid-ciphertext")

      expect { migration.up }.not_to raise_error
      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).not_to be_nil
    end

    # fc-38 round 4 re-review (LOW): DecryptionError was the only rescued
    # class — a key-rotation-gap error (the encryption key itself missing or
    # malformed, not just bad ciphertext) would raise straight through #up
    # and abort the ENTIRE db:migrate run, blocking every migration queued
    # to run after this one in the same invocation. Rescued per row instead:
    # skip that row, log the field name only, and keep going.
    it "leaves an encrypted password row alone and continues (does not raise) when decryption fails with a key error, not just bad ciphertext" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      AdminSetting.create!(key: "redis_config_password_encrypted", value: "irrelevant-ciphertext")
      allow(Security::CredentialEncryptionService).to receive(:decrypt_value)
        .and_raise(Security::CredentialEncryptionService::KeyNotFoundError, "Encryption key 'default' not found")

      expect { migration.up }.not_to raise_error
      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).not_to be_nil
    end

    it "also rescues InvalidKeyError without raising or destroying the row" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      AdminSetting.create!(key: "redis_config_password_encrypted", value: "irrelevant-ciphertext")
      allow(Security::CredentialEncryptionService).to receive(:decrypt_value)
        .and_raise(Security::CredentialEncryptionService::InvalidKeyError, "Invalid key format: must be base64 encoded")

      expect { migration.up }.not_to raise_error
      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).not_to be_nil
    end

    # fc-38 round 4 re-review (LOW): pins that ENV="" is treated identically
    # to ENV unset (both are blank), not as a genuine empty-string value to
    # compare stored values against.
    it "leaves a blob password and the encrypted row alone when REDIS_PASSWORD is the empty string, not just when it's nil" do
      ENV["REDIS_PASSWORD"] = ""
      seed_redis_config(password: "some-stored-password")
      AdminSetting.create!(
        key: "redis_config_password_encrypted",
        value: Security::CredentialEncryptionService.encrypt_value("some-encrypted-password")
      )

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "redis_config").value)
      expect(blob["password"]).to eq("some-stored-password")
      expect(AdminSetting.find_by(key: "redis_config_password_encrypted")).not_to be_nil
    end

    it "is a no-op (does not raise) when redis_config does not exist at all" do
      ENV["REDIS_PASSWORD"] = "current-env-password"
      ENV["REDIS_URL"] = "redis://:current-env-password@redis.internal:6379/0"

      expect { migration.up }.not_to raise_error
    end

    it "never says a plaintext ENV or ciphertext value — only field names and a count" do
      ENV["REDIS_PASSWORD"] = "current-env-password-for-log-check"
      ENV["REDIS_URL"] = "redis://:current-env-password-for-log-check@redis.internal:6379/0"
      seed_redis_config(password: "current-env-password-for-log-check", url: "redis://:current-env-password-for-log-check@redis.internal:6379/0")
      encrypted_value = Security::CredentialEncryptionService.encrypt_value("current-env-password-for-log-check")
      AdminSetting.create!(key: "redis_config_password_encrypted", value: encrypted_value)

      migration.up

      combined = said_messages.join("\n")
      expect(combined).not_to include("current-env-password-for-log-check")
      expect(combined).not_to include(encrypted_value)
      expect(combined).to match(/Stripped \d+ ENV-captured value/)
    end
  end

  describe "#down" do
    it "is irreversible — the captured value duplicated ENV, which still has it" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
