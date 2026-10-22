# frozen_string_literal: true

# Production never runs solid_cache in plain text: boot fails instead.
# See Powernode::CacheEncryptionGuard.
Rails.application.config.after_initialize do
  Powernode::CacheEncryptionGuard.check! if Rails.env.production?
end
