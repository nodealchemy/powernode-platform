# frozen_string_literal: true

module Ai
  module DataSources
    module Credentials
      # Immutable value object wrapping the SHORT-LIVED material a broker acquired
      # from an external authority (AWS STS, an OAuth2 token endpoint, a Vault
      # dynamic engine, an S3 presigner) so the existing signer layer can consume
      # it UNCHANGED.
      #
      # SIGNER CREDENTIAL CONTRACT (identical to QueryService::VaultCredentialView,
      # which Sigv4Signer / BearerSigner / etc. already read against):
      #   #decrypted_api_key    -> primary key/token
      #                            (OAuth access_token, AWS access_key_id, ...)
      #   #decrypted_api_secret -> secret (AWS secret_access_key, ...); may be nil
      #   #[](name)             -> any other field a signer reads off a plain Hash
      #                            (e.g. "session_token", "security_token")
      #
      # Tolerates the same common key spellings VaultCredentialView accepts so a
      # broker can return whatever the upstream named its fields:
      #   key    <= api_key | access_key_id | token | key   (in that order)
      #   secret <= api_secret | secret_access_key | secret (in that order)
      #
      # ADDITIONALLY exposes lease metadata used by BrokerCache + the brokers:
      #   #expires_at            -> absolute expiry (Time) or nil
      #   #expired?(skew=0)      -> true when now >= expires_at - skew (false if no expiry)
      #   #presigned_url         -> a fully-signed URL (PresignedUrlBroker) or nil
      #
      # SECURITY: this object NEVER logs, echoes, or inspects its material. #inspect
      # / #to_s are redacted so a token can never leak through an exception trace or
      # a `pp cred`. It is frozen on construction; the material Hash is duplicated
      # and indifferent so callers cannot mutate it underneath the signer.
      class BrokeredCredential
        # @param material [Hash] acquired short-lived secret material. String OR
        #   symbol keys both work (jsonb-tolerant). Common spellings recognized:
        #   api_key/access_key_id/token/key, api_secret/secret_access_key/secret,
        #   session_token, security_token, presigned_url. Any other key passes
        #   through #[].
        # @param expires_at [Time, nil] absolute lease expiry (UTC). nil => no expiry.
        def initialize(material, expires_at: nil)
          @material = indifferent(material || {}).freeze
          @expires_at = coerce_time(expires_at)
          freeze
        end

        # Primary key/token. Mirrors VaultCredentialView#decrypted_api_key spelling
        # order so existing signers read it identically.
        def decrypted_api_key
          @material["api_key"] || @material["access_key_id"] || @material["token"] || @material["key"]
        end

        # Secret half (may be nil for token-only schemes like OAuth bearer).
        def decrypted_api_secret
          @material["api_secret"] || @material["secret_access_key"] || @material["secret"]
        end

        # Pass-through for any other field a signer reads off a plain Hash
        # (e.g. "session_token", "security_token", "presigned_url"). Accepts a
        # String OR Symbol name.
        def [](name)
          @material[name]
        end

        # Absolute lease expiry, or nil when the broker did not supply one.
        # @return [Time, nil]
        attr_reader :expires_at

        # True when the lease has expired (or is within +skew_seconds+ of expiry).
        # A credential with NO expiry is never considered expired.
        #
        # @param skew_seconds [Integer] treat as expired this many seconds early.
        # @return [Boolean]
        def expired?(skew_seconds = 0)
          return false if @expires_at.nil?

          Time.current >= (@expires_at - skew_seconds.to_i)
        end

        # A fully pre-signed URL (set only by PresignedUrlBroker), else nil. Signers
        # that understand presigning can dispatch straight to this URL; the field is
        # also reachable via #["presigned_url"].
        def presigned_url
          @material["presigned_url"]
        end

        # Redacted — NEVER expose material. Both #inspect and #to_s so neither a
        # debugger, a `raise cred`, nor string interpolation can leak the token.
        def inspect
          "#<#{self.class.name} fields=#{@material.keys.sort.inspect} " \
            "expires_at=#{@expires_at&.utc&.iso8601 || 'none'}>"
        end
        alias to_s inspect

        private

        # Build a String|Symbol-indifferent read-only view of the material without
        # depending on ActiveSupport's HashWithIndifferentAccess semantics for
        # writes (we only ever read). Keys are stringified once; #[] re-stringifies
        # the lookup so symbol access works too.
        def indifferent(hash)
          src = hash.respond_to?(:to_h) ? hash.to_h : {}
          Indifferent.new(src)
        end

        def coerce_time(value)
          return nil if value.nil?
          return value if value.is_a?(Time)
          return Time.zone&.at(value) || Time.at(value) if value.is_a?(Numeric)

          Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        # Minimal frozen, read-only, String/Symbol-indifferent hash wrapper. Avoids
        # mutating the caller's Hash and guarantees the signer cannot write back.
        class Indifferent
          def initialize(source)
            @store = {}
            source.each { |k, v| @store[k.to_s] = v }
            @store.freeze
            freeze
          end

          def [](name)
            @store[name.to_s]
          end

          def keys
            @store.keys
          end

          def fetch(name, *args, &block)
            @store.fetch(name.to_s, *args, &block)
          end
        end
      end
    end
  end
end
