# frozen_string_literal: true

# fc-38 round 4 review (root-cause fix follow-up). ServiceConfiguration#
# update_redis_config used to deep-merge the ENV-merged `redis_config` read
# (default_redis_config's ENV["REDIS_PASSWORD"]/ENV["REDIS_URL"] defaults
# included) into whatever got saved, so ANY redis_config save made before
# this was fixed could have persisted a copy of the then-current ENV
# password/url into the blob — and, for password specifically, round 3's
# backfill (Admin::SystemSettings#strip_secret_keys_from_blob!) then
# ENCRYPTED that ENV-captured value into its own
# redis_config_password_encrypted row the next time a save ran. Because an
# encrypted row takes precedence over ENV at read time, that row shadows
# ENV forever: an operator rotating REDIS_PASSWORD and restarting would keep
# authenticating with the OLD captured password — a live, silent auth
# outage this migration exists to unwind.
#
# DISCRIMINATOR: a value is treated as "captured from ENV" only when it is
# IDENTICAL to the CURRENT ENV value (or, for "url", identical to either the
# raw current ENV URL or the userinfo-stripped form round 3's sanitizer
# could have produced from it) — the only signal available to tell "this
# was copied from ENV" apart from "an admin genuinely typed this,
# coincidentally the same value". A stored value that does NOT match
# current ENV (because ENV has since changed, or was unset at the time it
# was captured) cannot be told apart from a deliberate admin value with any
# confidence, so per review instruction it is LEFT ALONE rather than
# guessed at — a false positive here would delete a real admin-configured
# credential. If ENV["REDIS_PASSWORD"]/ENV["REDIS_URL"] is unset when this
# runs, nothing for that field is touched, for the same reason.
#
# NEVER logs, prints, or raises with a plaintext (or ciphertext, or ENV)
# VALUE in the message — only field names and counts, matching every other
# migration in this area's own rule.
#
# ENV-GATED: this cleanup only acts on a field when the corresponding ENV var
# (REDIS_PASSWORD / REDIS_URL) is PRESENT in the process that runs
# `db:migrate`. If db:migrate runs in an environment/shell where those vars
# aren't set (e.g. a deploy step with a different env than the one the app
# boots with), any pollution for that field is silently left in place — this
# migration will need re-running (or the vars supplying) once it does run
# with them present. See docs/operations/production-deployment.md for the
# operational note.
class StripEnvCapturedValuesFromRedisConfigBlob < ActiveRecord::Migration[8.0]
  def up
    cleaned = []
    cleaned << "redis_config.blob.password" if strip_blob_key_if_env_captured!("password", ENV["REDIS_PASSWORD"])
    cleaned << "redis_config.blob.url" if strip_blob_key_if_env_captured!("url", ENV["REDIS_URL"], also_match: sanitized_env_url)
    cleaned << "redis_config_password_encrypted" if clear_encrypted_row_if_env_captured!

    say "Stripped #{cleaned.size} ENV-captured value(s) that were shadowing ENV: #{cleaned.join(', ')}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "an ENV-captured value that was shadowing ENV is not something to restore — ENV still has it"
  end

  private

  # The userinfo-stripped form of the CURRENT ENV["REDIS_URL"] — this is
  # exactly what round 3's (buggy) sanitize_url_in_blob! would have written
  # into the blob after a save baked the raw ENV url in, so a blob "url"
  # matching THIS (not just the raw ENV url) is just as much a captured
  # value as an exact match.
  def sanitized_env_url
    return nil if ENV["REDIS_URL"].blank?

    uri = URI.parse(ENV["REDIS_URL"])
    return nil unless uri.userinfo.present?

    uri.user = nil
    uri.password = nil
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def strip_blob_key_if_env_captured!(field, env_value, also_match: nil)
    return false if env_value.blank?

    setting = AdminSetting.find_by(key: "redis_config")
    return false unless setting

    blob = parse_blob(setting.value)
    return false unless blob.is_a?(Hash) && blob.key?(field)
    return false unless blob[field] == env_value || (also_match.present? && blob[field] == also_match)

    blob.delete(field)
    setting.update!(value: blob.to_json)
    true
  end

  def clear_encrypted_row_if_env_captured!
    return false if ENV["REDIS_PASSWORD"].blank?

    row = AdminSetting.find_by(key: "redis_config_password_encrypted")
    return false unless row

    decrypted = Security::CredentialEncryptionService.decrypt_value(row.value)
    return false unless decrypted == ENV["REDIS_PASSWORD"]

    row.destroy!
    true
  rescue Security::CredentialEncryptionService::DecryptionError
    # An undecryptable row is corruption/rotation-gap territory (see
    # Admin::SystemSettings#decrypt_infrastructure_secret) — not this
    # migration's concern, and never something to compare a plaintext
    # ENV value against.
    false
  rescue Security::CredentialEncryptionService::InvalidKeyError, Security::CredentialEncryptionService::KeyNotFoundError => e
    # A key-service problem (missing/malformed encryption key) is not this
    # row's fault and not this migration's concern either — but letting it
    # raise would abort the ENTIRE db:migrate run, blocking every migration
    # queued to run after this one in the same invocation. Skip this row,
    # log only the field name and error class (never a value), keep going.
    say "Could not check redis_config_password_encrypted (#{e.class}); left in place"
    false
  end

  # A row whose value parses as valid JSON but isn't a Hash is skipped, not
  # raised on — matches 20260925020000's own rule.
  def parse_blob(raw)
    return raw if raw.is_a?(Hash)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
