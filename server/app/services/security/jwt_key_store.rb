# frozen_string_literal: true

module Security
  # Platform-global RS256 JWT signing keypair with multi-generation rotation.
  #
  # Durably stored via SecretStore (account: nil — the Vault-or-DB-encrypted seam),
  # so a rotation persists across processes and restarts. ENV (JWT_PRIVATE_KEY /
  # JWT_PUBLIC_KEY, loaded into config by config/initializers/jwt.rb) is the
  # FAIL-SAFE fallback: until the first rotation the store is empty and the ENV
  # keys are used (zero behavior change), and if the store is ever unreachable the
  # ENV keys keep auth working rather than outaging it.
  #
  # Two stored values (each a single SecretStore row, so each is internally
  # consistent even though the seam can't transact across Vault+DB):
  #   * ACTIVE_KEYPAIR        — JSON {private, public}; the current SIGNING key.
  #                             One row ⇒ the private/public pair can never tear.
  #   * VERIFICATION_KEYRING  — JSON [{pem, expires_at}, ...]; retired public keys
  #                             still inside their grace window. A LIST (not a
  #                             single slot) so several overlapping rotations all
  #                             keep verifying until each grace independently ends.
  #
  # Keys are cached in PROCESS MEMORY (never Rails.cache/Redis — the private key
  # must not sit in an unencrypted shared cache) with a short TTL, so all puma
  # workers converge on a rotation within CACHE_TTL seconds. On a verification
  # MISS the caller forces a throttled refresh (see #grace_verification_pems), so
  # a worker whose cache still holds the pre-rotation key picks up the new key
  # immediately instead of rejecting freshly-issued tokens for up to CACHE_TTL.
  module JwtKeyStore
    SCOPE              = "jwt_signing"
    ACTIVE_KEYPAIR     = "active_keypair"
    VERIFICATION_KEYRING = "verification_keyring"
    CACHE_TTL          = 60 # seconds — steady-state cache lifetime
    # Min gap between cache-bypass refreshes. Kept SMALL so that under a steady
    # stream of verification misses (including an attacker spraying invalid tokens
    # to keep the budget "spent") the refresh still fires roughly every second —
    # whoever triggers it repopulates the cache for everyone — so a worker lagging
    # a rotation converges within ~1s instead of waiting out CACHE_TTL, while store
    # reads stay bounded to ~1/sec/worker.
    FORCED_REFRESH_THROTTLE = 1 # seconds
    MAX_KEYRING_ENTRIES = 24 # bound verification cost (one day of hourly rotations)
    RSA_BITS           = 2048

    @mutex = Mutex.new
    @cache = {}
    @last_forced_refresh = nil

    class << self
      # PEM of the active private key for signing (store-backed; ENV fallback).
      def active_private_key_pem
        active_keypair["private"].presence || env_private_pem
      end

      # PEM of the active public key for verification (store-backed; ENV fallback).
      def active_public_key_pem
        active_keypair["public"].presence || env_public_pem
      end

      # Public-key PEMs to ATTEMPT after the active (cached) key fails to verify a
      # token. Forces a throttled cache-bypass refresh first, so a worker lagging a
      # rotation re-reads the NEW active key (fixes new-key tokens being rejected
      # during convergence) and the freshest keyring, then returns the refreshed
      # active key plus every retired key still inside its grace window.
      def grace_verification_pems
        force_refresh!
        ([active_public_key_pem] + grace_public_pems).compact.uniq
      end

      # Retired public-key PEMs still within their grace window (may be empty).
      def grace_public_pems
        now = Time.current
        keyring.filter_map do |entry|
          pem = entry["pem"].presence
          ends = entry["expires_at"].presence
          next unless pem && ends

          (Time.parse(ends) > now ? pem : nil)
        rescue ArgumentError
          nil
        end
      end

      # True while at least one retired key is still inside its grace window.
      def within_grace?
        grace_public_pems.any?
      end

      # Rotate the signing keypair: generate a fresh RSA keypair IN CODE (never via
      # a CLI/shell command, per the crypto-safety rules), make it the active
      # signing key, and add the prior public key to the verification keyring for
      # the grace window so in-flight tokens still verify. Returns metadata only
      # (NO key material). New tokens are signed with the new key once each
      # process's cache refreshes (<= CACHE_TTL, or immediately on a verify miss).
      def rotate!(grace_hours:)
        new_key    = OpenSSL::PKey::RSA.generate(RSA_BITS)
        old_public = uncached_active_public_pem # cache-bypass: avoid retaining a stale generation
        grace_ends = grace_hours.hours.from_now

        # Prune expired entries, then append the just-retired public key. Write the
        # keyring FIRST and flip the active keypair LAST: a partial failure leaves
        # at worst a redundant keyring entry for the still-active key (benign).
        ring = keyring.reject { |e| expired?(e) }
        ring << { "pem" => old_public, "expires_at" => grace_ends.iso8601 } if old_public.present?
        ring = ring.last(MAX_KEYRING_ENTRIES) # cap growth — bounds per-token verify cost

        write(VERIFICATION_KEYRING, ring.to_json)
        write(ACTIVE_KEYPAIR, { "private" => new_key.to_pem, "public" => new_key.public_key.to_pem }.to_json)
        clear_cache!

        { rotated_at: Time.current, grace_ends_at: grace_ends }
      end

      # True once a rotation has populated the store (active keypair present).
      def store_populated?
        read(ACTIVE_KEYPAIR).present?
      rescue StandardError
        false
      end

      def clear_cache!
        @mutex.synchronize do
          @cache = {}
          @last_forced_refresh = nil # a cleared cache may refresh immediately
        end
      end

      private

      def active_keypair
        raw = fetch(ACTIVE_KEYPAIR).presence
        raw ? (JSON.parse(raw) rescue {}) : {}
      end

      def keyring
        raw = fetch(VERIFICATION_KEYRING).presence
        raw ? (Array(JSON.parse(raw)) rescue []) : []
      end

      def expired?(entry)
        ends = entry["expires_at"].presence
        return true unless ends

        Time.parse(ends) <= Time.current
      rescue ArgumentError
        true
      end

      # Public PEM of the active keypair read straight from the store (no cache),
      # so a rotation never retains a stale generation as the "previous" key.
      def uncached_active_public_pem
        raw = read(ACTIVE_KEYPAIR).presence
        (raw ? (JSON.parse(raw)["public"] rescue nil) : nil).presence || env_public_pem
      rescue StandardError
        env_public_pem
      end

      # Drop the cached active keypair + keyring so the next read is fresh — at most
      # once per FORCED_REFRESH_THROTTLE seconds, bounding store load under a flood
      # of bogus tokens. A no-op if a refresh happened recently (cache already
      # fresh), in which case the already-tried active key is current.
      def force_refresh!
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @mutex.synchronize do
          return if @last_forced_refresh && (now - @last_forced_refresh) < FORCED_REFRESH_THROTTLE

          @last_forced_refresh = now
          @cache.delete(ACTIVE_KEYPAIR)
          @cache.delete(VERIFICATION_KEYRING)
        end
      end

      # Short-TTL in-process memoization. On any store error, returns nil so the
      # caller falls back to the ENV key — auth never outages on a store blip. The
      # error path does NOT cache, so a transient blip can't pin an empty value.
      def fetch(key)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @mutex.synchronize do
          entry = @cache[key]
          return entry[:value] if entry && entry[:expires_at] > now
        end

        value = read(key)
        @mutex.synchronize { @cache[key] = { value: value, expires_at: now + CACHE_TTL } }
        value
      rescue StandardError => e
        Rails.logger.warn("[JwtKeyStore] store read failed for #{key}: #{e.class}: #{e.message}")
        nil
      end

      def read(key)
        Security::SecretStore.read(account: nil, scope: SCOPE, key: key)
      end

      def write(key, value)
        Security::SecretStore.write(account: nil, scope: SCOPE, key: key, value: value)
      end

      # ENV-derived PEMs (loaded into config by config/initializers/jwt.rb under
      # RS256). The accessors are only defined when assigned, so guard with
      # respond_to? — returns nil when unset (e.g. HS256 deployments) instead of
      # raising a cryptic NoMethodError deep inside a rotation.
      def env_private_pem
        config = Rails.application.config
        config.respond_to?(:jwt_private_key) ? config.jwt_private_key : nil
      end

      def env_public_pem
        config = Rails.application.config
        config.respond_to?(:jwt_public_key) ? config.jwt_public_key : nil
      end
    end
  end
end
