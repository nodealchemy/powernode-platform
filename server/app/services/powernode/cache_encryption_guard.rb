# frozen_string_literal: true

module Powernode
  # Refuses to boot production on a solid_cache store that would keep its
  # entries in plain text. Everything the app caches lands in
  # solid_cache_entries (OAuth PKCE verifiers among it) and in every database
  # backup, so production encrypts them (config/cache.yml `encrypt: true`,
  # Active Record Encryption). Missing any of the three AR encryption keys, or
  # the encrypt flag itself, is a boot failure: never a silent fallback to
  # plain text. Run from config/initializers/solid_cache_encryption_guard.rb.
  module CacheEncryptionGuard
    class Unencrypted < StandardError; end

    KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

    module_function

    def check!(store: Rails.cache, encrypt: solid_cache_encrypt?, encryption_config: -> { ActiveRecord::Encryption.config })
      return unless defined?(::SolidCache::Store) && store.is_a?(::SolidCache::Store)

      unless encrypt
        raise Unencrypted, "solid_cache would store entries in plain text: set encrypt: true for this " \
                           "environment in config/cache.yml"
      end

      config = encryption_config.call
      missing = KEYS.select { |key| Array(config.public_send(key)).compact_blank.empty? }
      return if missing.empty?

      raise Unencrypted, "solid_cache encryption needs the Active Record encryption #{missing.join(', ')} " \
                         "(ACTIVE_RECORD_ENCRYPTION_* or credentials)"
    rescue Unencrypted
      raise
    rescue StandardError => e
      raise Unencrypted, "solid_cache encryption cannot resolve the Active Record encryption keys (#{e.class})"
    end

    def solid_cache_encrypt?
      defined?(::SolidCache) && ::SolidCache.configuration&.encrypt? ? true : false
    end
  end
end
