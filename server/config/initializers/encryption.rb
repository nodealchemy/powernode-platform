# frozen_string_literal: true

# Sibling initializer `00_ar_encryption_inspect_redaction.rb` runs first
# (alphabetical ordering) and patches `inspect` on every
# ActiveRecord::Encryption class that holds key material BEFORE any
# encryption code in this file can run. Without that patch, exception
# messages from anywhere in the encryption stack leak keys through
# Ruby's default `inspect` (NoMethodError#message includes
# inspect-of-receiver).

# ActiveRecord Encryption Configuration
#
# Rails 8.1.3 changed encryption key resolution: the railtie now calls
# ActiveRecord::Encryption.configure() with credentials as named kwargs,
# which override any keys set via config.active_record.encryption.*.
# We hook into the same on_load lifecycle to run AFTER the railtie and
# call configure() directly with the resolved keys.
#
# Key rotation: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY and DETERMINISTIC_KEY
# accept comma-separated lists. Rails 8's KeyProvider#encryption_key returns
# `@keys.last` — the LAST entry is used for new writes, and ALL entries are
# tried for reads. **Order matters and is counterintuitive.** Rotation:
#   1. Generate new keys; set env to "OLD,NEW" — OLD first (read fallback),
#      NEW last (active write key).
#   2. Restart backend.
#   3. Run `bin/rails ar_encryption:re_encrypt_all` — writes use NEW.
#   4. Set env back to just "NEW"; restart. OLD is no longer trusted.
#
# (The salt is single-value only — PBKDF2 needs a string.)
ActiveSupport.on_load(:active_record_encryption) do
  # `multi:` controls whether an env value is allowed to be a comma-
  # separated key list (array) or must be a single string.
  #
  #   - primary_key + deterministic_key: array-OK (DerivedSecretKeyProvider
  #     tries each in order; first is used for new writes). Necessary for
  #     rotation: env="NEW,OLD" → write with NEW, read with either.
  #   - key_derivation_salt: STRING ONLY. It's the salt argument to
  #     PBKDF2 inside KeyGenerator, which would TypeError on Array. If
  #     the env value contains commas (legacy / accidental), take only
  #     the first entry to stay safe. To actually rotate the salt, run a
  #     re-encrypt cycle for each old salt sequentially — not via this
  #     env mechanism.
  resolve = ->(env_var, credential_path, fallback, multi:) {
    raw = ENV[env_var]
    if raw && !raw.empty?
      entries = raw.split(",").map(&:strip).reject(&:empty?)
      return multi ? (entries.size == 1 ? entries.first : entries) : entries.first
    end
    Rails.application.credentials.dig(*credential_path) ||
      (Rails.env.local? ? fallback : raise("ActiveRecord encryption #{credential_path.last} not configured"))
  }

  primary_key         = resolve.call("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
                                      %i[active_record_encryption primary_key],
                                      "mHKA6Hni3W6tRlGEdmCgs9uS9q4yPWi2", multi: true)
  deterministic_key   = resolve.call("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
                                      %i[active_record_encryption deterministic_key],
                                      "EikFNeuXUdH8iPXJwatYeLzbu3v9kgN5", multi: true)
  key_derivation_salt = resolve.call("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
                                      %i[active_record_encryption key_derivation_salt],
                                      "fwpUiks80xeR4dolB6CsGbkUWnkrluwZ", multi: false)

  ActiveRecord::Encryption.configure(
    primary_key:              primary_key,
    deterministic_key:        deterministic_key,
    key_derivation_salt:      key_derivation_salt,
    support_unencrypted_data: true,
    extend_queries:           true
  )

  if defined?(Rails.logger)
    Rails.logger.info "ActiveRecord Encryption configured"
  end
end
