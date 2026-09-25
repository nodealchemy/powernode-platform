# frozen_string_literal: true

# fc-38 decision #3: AdminSettings::InfrastructureConfigActions stored
# redis_config's "password" and vault_config's "vault_role_id"/
# "vault_secret_id" as PLAINTEXT inside their JSON blobs (confirmed by
# reading code only — no live DB was queried and no value was ever printed
# while investigating this). From here on they're separate
# Security::CredentialEncryptionService-encrypted rows
# (redis_config_password_encrypted, vault_role_id_encrypted,
# vault_secret_id_encrypted — the same mechanism EmailSettingsController
# already used for smtp_password_encrypted etc), read/written exclusively
# through Admin::SystemSettings#redis_config/#update_redis_config!/
# #vault_config/#update_vault_config! now.
#
# Idempotent by construction: each field's own "already migrated" check is
# "does its _encrypted row already exist", not a flag on the source blob, so
# re-running this (or running it against a blob some other write already
# stripped the field from) is a no-op for that field.
#
# NEVER logs, prints, or raises with a plaintext (or ciphertext) VALUE in the
# message — only field names and counts, matching
# 20260925010000_delete_garbage_admin_settings_nested_writer_rows.rb's own
# rule. Security::CredentialEncryptionService.encrypt_value can raise
# EncryptionError, whose message wraps the UNDERLYING crypto error, never the
# plaintext it was given — left unrescued here so a genuine encryption
# failure aborts the migration instead of silently leaving a field
# unmigrated.
class EncryptPlaintextRedisAndVaultAdminSettings < ActiveRecord::Migration[8.0]
  def up
    migrated = []
    migrated << "redis_config.password" if migrate_field!(blob_key: "redis_config", field: "password", encrypted_key: "redis_config_password_encrypted")
    migrated << "vault_config.vault_role_id" if migrate_field!(blob_key: "vault_config", field: "vault_role_id", encrypted_key: "vault_role_id_encrypted")
    migrated << "vault_config.vault_secret_id" if migrate_field!(blob_key: "vault_config", field: "vault_secret_id", encrypted_key: "vault_secret_id_encrypted")

    say "Encrypted #{migrated.size} plaintext field(s) in place: #{migrated.join(', ')}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "plaintext values were removed from their blobs once encrypted; nothing to restore"
  end

  private

  # Returns true only when a NEW encrypted row was created (existing
  # plaintext moved into it) — the caller's count is "how many fields did I
  # just encrypt", not "how many fields did I touch". Regardless of that
  # return value, a plaintext `field` key present in the blob is ALWAYS
  # stripped when found (fc-38 review item #3(a)): the old "already migrated"
  # check short-circuited on `encrypted_key` existing BEFORE ever looking at
  # the blob, so a blob that still carried the plaintext key — because the
  # encrypted row was created some OTHER way, e.g. a fresh save through the
  # now-hardened write path run before this migration — kept its plaintext
  # forever. An already-existing encrypted row's value is never touched.
  def migrate_field!(blob_key:, field:, encrypted_key:)
    setting = AdminSetting.find_by(key: blob_key)
    return false unless setting

    config = parse_blob(setting.value)
    return false unless config.is_a?(Hash) && config.key?(field)

    value = config[field]
    newly_encrypted = false

    if value.present? && !AdminSetting.exists?(key: encrypted_key)
      AdminSetting.create!(key: encrypted_key, value: Security::CredentialEncryptionService.encrypt_value(value))
      newly_encrypted = true
    end

    config.delete(field)
    setting.update!(value: config.to_json)

    newly_encrypted
  end

  # A row whose value parses as valid JSON but isn't a Hash (fc-38 review
  # item #6 — not the shape this migration expects, but not impossible) is
  # skipped, not raised on: the caller's `config.is_a?(Hash) && ...` check
  # handles that once this returns whatever JSON.parse gave it, Hash or not.
  def parse_blob(raw)
    return raw if raw.is_a?(Hash)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
