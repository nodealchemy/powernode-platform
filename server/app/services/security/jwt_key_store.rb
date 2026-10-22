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
  #
  # HS256 has the same shape beside it (the hub runs HS256 in production):
  #   * ACTIVE_HMAC_SECRET   — the current signing secret.
  #   * HMAC_KEYRING         — JSON [{secret, expires_at}, ...]; retired secrets
  #                            still inside their grace window.
  # JWT_SECRET_KEY (config.jwt_secret_key) is only the BOOTSTRAP value, used
  # while the store holds no secret: an absent row, or Vault's "not found" for
  # a path never written, is "readable but empty". A store that cannot be
  # REACHED (Vault connection error, BackendUnavailable, an AR connection
  # error) serves the last secrets this process loaded; only when it has never
  # loaded any does it FAIL CLOSED (StoreUnavailable, which authentication
  # answers with 503). Falling back to JWT_SECRET_KEY there would sign and
  # accept with the very secret a rotation retired. Nothing HS256 is ever
  # written to Rails.cache.
  #
  # Scope of an HS256 rotation: tokens this server signs and verifies (user,
  # impersonation, API). Server-to-worker job JWTs are NOT covered: the worker
  # verifies them with its own JWT_SECRET_KEY, so they are always signed with
  # JWT_SECRET_KEY (#worker_auth_secret), which rotates through the secrets
  # file and a restart of server and worker.
  #
  # Every store read here passes `cache: false`, so on a Vault backend a
  # refresh really re-reads Vault instead of VaultClient's 5-minute cache.
  module JwtKeyStore
    class StoreUnavailable < StandardError; end

    SCOPE              = "jwt_signing"
    ACTIVE_KEYPAIR     = "active_keypair"
    VERIFICATION_KEYRING = "verification_keyring"
    ACTIVE_HMAC_SECRET = "active_hmac_secret"
    HMAC_KEYRING       = "hmac_keyring"
    HMAC_SECRET_BYTES  = 64 # hex-encoded: a 128-character secret
    # Store errors that mean "cannot reach the store", as opposed to "the store
    # answered and holds nothing" (nil, or Vault's SecretNotFoundError).
    # The database half matches solid_cache's own transient list
    # (SolidCache::Store::Failsafe): a cancelled or timed-out query is an outage,
    # not a bad token.
    UNREACHABLE_ERRORS = [
      Security::SecretStore::BackendUnavailable,
      Security::VaultClient::ConnectionError,
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::ConnectionTimeoutError,
      ActiveRecord::AdapterTimeout,
      ActiveRecord::Deadlocked,
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::QueryCanceled,
      ActiveRecord::StatementTimeout
    ].freeze
    # SiteSetting recorded by every HS256 rotation, OUTSIDE the secret path.
    # Once set, an "empty" active secret is an error (wrong Vault mount or
    # namespace, reconfigured Vault, database restored from before the
    # rotation), never a reason to fall back to the retired JWT_SECRET_KEY.
    ROTATION_MARKER = "jwt_hmac_rotated_at"
    # How long a last-known secret may be served while the store is
    # unreachable, from its last successful load. Equal to the rotation grace
    # period (Admin::SecurityConfigService::JWT_ROTATION_GRACE_PERIOD, 24h), so
    # an outage cannot keep a secret alive longer than a rotation would.
    STALE_SERVE_LIMIT = 24.hours
    CACHE_TTL          = 60 # seconds — steady-state cache lifetime
    # Min gap between cache-bypass refreshes. Kept SMALL so that under a steady
    # stream of verification misses (including an attacker spraying invalid tokens
    # to keep the budget "spent") the refresh still fires roughly every second —
    # whoever triggers it repopulates the cache for everyone — so a worker lagging
    # a rotation converges within ~1s instead of waiting out CACHE_TTL, while store
    # reads stay bounded to ~1/sec/worker.
    FORCED_REFRESH_THROTTLE = 1 # seconds
    # On a Vault backend every forced refresh is a Vault round trip per key, so
    # the floor there is higher.
    VAULT_FORCED_REFRESH_THROTTLE = 5 # seconds
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

      # The HS256 signing secret: the stored active secret, or JWT_SECRET_KEY
      # while nothing has been rotated. Raises StoreUnavailable when the store
      # cannot be read.
      def active_hmac_secret
        stored = fetch_strict(ACTIVE_HMAC_SECRET).presence
        if stored
          warn_unrecorded_rotation unless rotation_recorded?
          return stored
        end

        if rotation_recorded?
          raise StoreUnavailable, "the store holds no active HS256 secret although a rotation is recorded " \
                                  "(#{ROTATION_MARKER}); refusing to fall back to JWT_SECRET_KEY"
        end

        env_hmac_secret
      end

      # Retired HS256 secrets still inside their grace window (may be empty).
      # Raises StoreUnavailable when the store cannot be read.
      def hmac_grace_secrets
        hmac_ring(fetch_strict(HMAC_KEYRING)).reject { |e| expired?(e) }.filter_map { |e| e["secret"].presence }
      end

      # Every HS256 secret a token may verify against: the active one first,
      # then the unexpired ring. `refresh: true` re-reads the store first
      # (throttled, as for RSA), for the one retry after a verification miss,
      # so a process still holding the pre-rotation secret accepts tokens
      # signed with the new one.
      def hmac_verification_secrets(refresh: false)
        force_refresh! if refresh
        ([ active_hmac_secret ] + hmac_grace_secrets).compact.uniq
      end

      # The secret server-to-worker job JWTs are signed with: always
      # JWT_SECRET_KEY, the value the worker verifies with. Never the rotated
      # user-token secret (see the module comment).
      def worker_auth_secret
        env_hmac_secret || raise(StoreUnavailable, "JWT_SECRET_KEY is not configured")
      end

      # Rotate the HS256 secret: generated IN CODE, never on a CLI. Prunes
      # expired ring entries, appends the retiring secret with its grace end,
      # writes the ring FIRST and the new active secret LAST (a partial failure
      # leaves at worst a redundant ring entry). Reads bypass the cache and fail
      # closed. Returns metadata only, never a secret.
      def rotate_hmac!(grace_hours:)
        new_secret = SecureRandom.hex(HMAC_SECRET_BYTES)
        old_secret = read_strict(ACTIVE_HMAC_SECRET).presence || env_hmac_secret
        grace_ends = grace_hours.hours.from_now

        ring = hmac_ring(read_strict(HMAC_KEYRING)).reject { |e| expired?(e) }
        ring << { "secret" => old_secret, "expires_at" => grace_ends.iso8601 } if old_secret.present?
        ring = ring.last(MAX_KEYRING_ENTRIES)

        write(HMAC_KEYRING, ring.to_json)
        write(ACTIVE_HMAC_SECRET, new_secret)
        rotated_at = Time.current
        record_rotation_marker(rotated_at)
        clear_cache!

        { rotated_at: rotated_at, grace_ends_at: grace_ends }
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
          @stale_warned_at = {}
          @vault_backend = nil
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
        end
        if vault_backend?(now)
          @mutex.synchronize do
            return if @last_forced_refresh && (now - @last_forced_refresh) < VAULT_FORCED_REFRESH_THROTTLE
          end
        end
        @mutex.synchronize do
          @last_forced_refresh = now
          # Mark stale rather than delete: the HS256 path serves the last-known
          # value when the store is unreachable, so it must survive a refresh.
          [ ACTIVE_KEYPAIR, VERIFICATION_KEYRING, ACTIVE_HMAC_SECRET, HMAC_KEYRING ].each do |key|
            @cache[key] = @cache[key].merge(expires_at: 0) if @cache[key]
          end
        end
      end

      # Whether the secret backend is Vault, memoized for CACHE_TTL so a flood
      # of verification misses costs no extra setting reads. Unknown => false
      # (the 1s floor still applies).
      def vault_backend?(now)
        @mutex.synchronize do
          return @vault_backend[:value] if @vault_backend && @vault_backend[:expires_at] > now
        end
        value = Security::SecretStore.backend == :vault
        @mutex.synchronize { @vault_backend = { value: value, expires_at: now + CACHE_TTL } }
        value
      rescue StandardError
        false
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

      # As #fetch for the HS256 path. When the store is unreachable, or answers
      # empty after this process had loaded a real value, it serves that
      # last-known value for up to STALE_SERVE_LIMIT from its last successful
      # load, then raises StoreUnavailable; with nothing loaded it raises at
      # once. Never caches an error, and never replaces a real value with nil.
      def fetch_strict(key)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last_known = nil
        @mutex.synchronize do
          last_known = @cache[key]
          return last_known[:value] if last_known && last_known[:expires_at] > now
        end

        value =
          begin
            read_strict(key)
          rescue StoreUnavailable
            raise unless last_known

            return serve_last_known(key, last_known, now, "store unreachable")
          end

        if value.nil? && last_known && !last_known[:value].nil?
          return serve_last_known(key, last_known, now, "store answered empty after a real value")
        end

        @mutex.synchronize { @cache[key] = { value: value, expires_at: now + CACHE_TTL, loaded_at: Time.current } }
        value
      end

      def serve_last_known(key, last_known, now, why)
        loaded_at = last_known[:loaded_at]
        if loaded_at.nil? || Time.current - loaded_at > STALE_SERVE_LIMIT
          raise StoreUnavailable, "JWT key store: #{why}, and the last-known #{key} is older than " \
                                  "#{STALE_SERVE_LIMIT.inspect}"
        end

        warn_stale_once(key, now, why)
        last_known[:value]
      end

      # One warning per key per CACHE_TTL during an outage, not one per request.
      def warn_stale_once(key, now, why)
        warn_once(key, now, "#{why}; serving the last-known #{key}")
      end

      def warn_once(key, now, message)
        @stale_warned_at ||= {}
        log = @mutex.synchronize do
          last = @stale_warned_at[key]
          next false if last && (now - last) < CACHE_TTL

          @stale_warned_at[key] = now
          true
        end
        Rails.logger.warn("[JwtKeyStore] #{message}") if log
      end

      # A stored secret with no recorded rotation means the marker was cleared (or
      # never written) while the secret stayed: the fail-closed guard is off, and
      # the next empty store would fall back to JWT_SECRET_KEY. Logged once per
      # CACHE_TTL, like the stale-serve warning.
      def warn_unrecorded_rotation
        warn_once(:unrecorded_rotation, Process.clock_gettime(Process::CLOCK_MONOTONIC),
                        "the store holds an HS256 secret but #{ROTATION_MARKER} is not set; an empty " \
                        "store would fall back to JWT_SECRET_KEY")
      end

      # Best effort: the secrets are already written and are what verification
      # needs; the marker only guards against a later empty store. A failure is
      # logged loudly, never raised, so it cannot fail a rotation that landed.
      def record_rotation_marker(rotated_at)
        ::SiteSetting.set(ROTATION_MARKER, rotated_at.iso8601, setting_type: "string")
      rescue StandardError => e
        Rails.logger.error("[JwtKeyStore] HS256 rotation landed but #{ROTATION_MARKER} could not be " \
                           "recorded (#{e.class}); an empty store would fall back to JWT_SECRET_KEY")
      end

      # Whether a rotation was ever recorded. Sticky once true; a false answer
      # is re-checked after CACHE_TTL. When the database is unreachable the
      # last-known answer serves (as #fetch_strict does for the secrets, within
      # STALE_SERVE_LIMIT); with none it raises StoreUnavailable.
      def rotation_recorded?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last_known = nil
        @mutex.synchronize do
          last_known = @cache[ROTATION_MARKER]
          return true if last_known && last_known[:value]
          return false if last_known && last_known[:expires_at] > now
        end

        recorded =
          begin
            ::SiteSetting.get(ROTATION_MARKER).present?
          rescue *UNREACHABLE_ERRORS => e
            raise StoreUnavailable, "JWT rotation marker unreadable (#{e.class})" unless last_known

            return serve_last_known(ROTATION_MARKER, last_known, now, "rotation marker unreadable")
          end
        @mutex.synchronize do
          @cache[ROTATION_MARKER] = { value: recorded, expires_at: now + CACHE_TTL, loaded_at: Time.current }
        end
        recorded
      end

      # nil when the store answered and holds nothing; StoreUnavailable when it
      # cannot be reached. Any other error propagates unchanged (still refused).
      def read_strict(key)
        read(key)
      rescue Security::VaultClient::SecretNotFoundError
        nil
      rescue *UNREACHABLE_ERRORS => e
        Rails.logger.error("[JwtKeyStore] store read failed for #{key}: #{e.class}")
        raise StoreUnavailable, "JWT key store unavailable (#{e.class})"
      end

      def hmac_ring(raw)
        return [] if raw.blank?

        Array(JSON.parse(raw)).select { |e| e.is_a?(Hash) }
      rescue JSON::ParserError
        []
      end

      # cache: false — JwtKeyStore's own short in-process cache is the only
      # cache; a Vault backend's 5-minute VaultClient cache would defeat the
      # forced refresh.
      def read(key)
        Security::SecretStore.read(account: nil, scope: SCOPE, key: key, cache: false)
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

      # JWT_SECRET_KEY, the HS256 bootstrap secret (config/initializers/jwt.rb).
      def env_hmac_secret
        config = Rails.application.config
        config.respond_to?(:jwt_secret_key) ? config.jwt_secret_key.presence : nil
      end
    end
  end
end
