# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260925020000_encrypt_plaintext_redis_and_vault_admin_settings.rb")

# fc-38 decision #3 — moves redis_config's "password" and vault_config's
# "vault_role_id"/"vault_secret_id" out of plaintext AdminSetting JSON blobs
# into separate Security::CredentialEncryptionService-encrypted rows.
RSpec.describe EncryptPlaintextRedisAndVaultAdminSettings do
  subject(:migration) { described_class.new }

  # Captures every #say call's MESSAGE rather than letting it hit real
  # stdout, so this spec can assert on it — the requirement under test is
  # "never logs, prints, or raises with a value", so the messages themselves
  # are the thing being checked.
  let(:said_messages) { [] }

  before do
    allow(migration).to receive(:say) { |msg, *| said_messages << msg }
  end

  def seed_redis_config(password:)
    AdminSetting.create!(
      key: "redis_config",
      value: { "host" => "127.0.0.1", "port" => 6379, "password" => password }.to_json
    )
  end

  def seed_vault_config(vault_addr: "http://vault.internal:8200", vault_role_id: nil, vault_secret_id: nil)
    blob = { "vault_addr" => vault_addr }
    blob["vault_role_id"] = vault_role_id if vault_role_id
    blob["vault_secret_id"] = vault_secret_id if vault_secret_id
    AdminSetting.create!(key: "vault_config", value: blob.to_json)
  end

  describe "#up" do
    # fc-38 review item #6: a row whose value parses as valid JSON but ISN'T
    # a Hash (e.g. a bare array or number — not the shape this migration
    # expects, but not impossible if something else ever wrote one) must be
    # skipped, not raise and abort the whole migration mid-boot.
    it "skips (does not raise) a redis_config row whose value is valid JSON but not a Hash" do
      AdminSetting.create!(key: "redis_config", value: "[1,2,3]")

      expect { migration.up }.not_to raise_error
      expect(AdminSetting.exists?(key: "redis_config_password_encrypted")).to be(false)
    end

    it "does nothing when neither redis_config nor vault_config rows exist" do
      expect { migration.up }.not_to raise_error

      expect(AdminSetting.exists?(key: "redis_config_password_encrypted")).to be(false)
      expect(AdminSetting.exists?(key: "vault_role_id_encrypted")).to be(false)
      expect(AdminSetting.exists?(key: "vault_secret_id_encrypted")).to be(false)
    end

    it "encrypts an existing plaintext redis_config password in place" do
      password = "redis-migration-secret-#{SecureRandom.hex(4)}"
      seed_redis_config(password: password)

      migration.up

      blob = AdminSetting.find_by(key: "redis_config").value
      expect(blob).not_to include(password)
      expect(JSON.parse(blob)).not_to have_key("password")

      encrypted = AdminSetting.find_by(key: "redis_config_password_encrypted")
      expect(encrypted).not_to be_nil
      expect(encrypted.value).not_to include(password)
      expect(Security::CredentialEncryptionService.decrypt_value(encrypted.value)).to eq(password)
    end

    it "encrypts existing plaintext vault_role_id and vault_secret_id in place, leaving vault_addr untouched" do
      role_id = "role-migration-#{SecureRandom.hex(4)}"
      secret_id = "secret-migration-#{SecureRandom.hex(4)}"
      seed_vault_config(vault_addr: "http://vault.example.internal:8200", vault_role_id: role_id, vault_secret_id: secret_id)

      migration.up

      blob = JSON.parse(AdminSetting.find_by(key: "vault_config").value)
      expect(blob).to eq("vault_addr" => "http://vault.example.internal:8200")

      role_row = AdminSetting.find_by(key: "vault_role_id_encrypted")
      secret_row = AdminSetting.find_by(key: "vault_secret_id_encrypted")
      expect(Security::CredentialEncryptionService.decrypt_value(role_row.value)).to eq(role_id)
      expect(Security::CredentialEncryptionService.decrypt_value(secret_row.value)).to eq(secret_id)
    end

    # fc-38 review item #3(a): the "already migrated" check
    # (AdminSetting.exists?(key: encrypted_key)) used to short-circuit BEFORE
    # ever looking at the blob, so a blob that still carried the plaintext
    # key — because the encrypted row was created some OTHER way (a fresh
    # save through the now-hardened write path, run before this migration) —
    # kept its plaintext forever. The blob must be stripped regardless of
    # whether the encrypted row already existed; the existing row's value
    # (and the credential it decrypts to) must not change.
    it "strips a leftover plaintext password from the blob even when the encrypted row already exists" do
      already_encrypted = Security::CredentialEncryptionService.encrypt_value("already-encrypted-real-password")
      AdminSetting.create!(key: "redis_config_password_encrypted", value: already_encrypted)
      seed_redis_config(password: "leftover-plaintext-in-blob")

      migration.up

      blob = AdminSetting.find_by(key: "redis_config").value
      expect(JSON.parse(blob)).not_to have_key("password")
      expect(AdminSetting.find_by(key: "redis_config_password_encrypted").value).to eq(already_encrypted)
    end

    it "is a no-op for a redis_config row with no password key" do
      AdminSetting.create!(key: "redis_config", value: { "host" => "127.0.0.1" }.to_json)

      expect { migration.up }.not_to raise_error
      expect(AdminSetting.exists?(key: "redis_config_password_encrypted")).to be(false)
    end

    it "is idempotent: running twice does not re-encrypt or error" do
      password = "redis-idempotent-#{SecureRandom.hex(4)}"
      seed_redis_config(password: password)

      migration.up
      first_pass_ciphertext = AdminSetting.find_by(key: "redis_config_password_encrypted").value

      expect { migration.up }.not_to raise_error
      second_pass_ciphertext = AdminSetting.find_by(key: "redis_config_password_encrypted").value

      expect(second_pass_ciphertext).to eq(first_pass_ciphertext)
      expect(Security::CredentialEncryptionService.decrypt_value(second_pass_ciphertext)).to eq(password)
    end

    it "never says a plaintext or ciphertext value — only field names and a count" do
      redis_password = "redis-log-check-#{SecureRandom.hex(4)}"
      role_id = "role-log-check-#{SecureRandom.hex(4)}"
      secret_id = "secret-log-check-#{SecureRandom.hex(4)}"
      seed_redis_config(password: redis_password)
      seed_vault_config(vault_role_id: role_id, vault_secret_id: secret_id)

      migration.up

      encrypted_values = AdminSetting.where(key: %w[redis_config_password_encrypted vault_role_id_encrypted vault_secret_id_encrypted]).pluck(:value)

      combined = said_messages.join("\n")
      expect(combined).not_to include(redis_password)
      expect(combined).not_to include(role_id)
      expect(combined).not_to include(secret_id)
      encrypted_values.each { |ciphertext| expect(combined).not_to include(ciphertext) }
      expect(combined).to match(/Encrypted \d+ plaintext field/)
    end
  end

  describe "#down" do
    it "is irreversible — the plaintext is gone the moment it's encrypted" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
