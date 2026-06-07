# frozen_string_literal: true

require "openssl"
require "base64"

module Security
  # Shared HTTP-signature primitives.
  #
  # Extracted from Chat::WebhookVerificationService so both the *inbound*
  # webhook verification path and the *outbound* request-signing path
  # (Ai::DataSources::Auth::HmacSigner) share one audited implementation of
  # HMAC computation, canonicalization helpers and constant-time comparison.
  #
  # All methods are module functions — there is no instance state. The module
  # deliberately knows nothing about Faraday, ActiveRecord or Vault; callers
  # supply already-resolved secrets and pre-canonicalized strings.
  module HttpSignature
    module_function

    # Supported HMAC digest algorithms keyed by a normalized lowercase name.
    # OpenSSL accepts the uppercase digest name; we normalize on the way in so
    # callers may pass "sha256", "SHA-256", "hmac-sha256", etc.
    SUPPORTED_ALGORITHMS = {
      "sha256" => "SHA256",
      "sha384" => "SHA384",
      "sha512" => "SHA512",
      "sha1"   => "SHA1"
    }.freeze

    DEFAULT_ALGORITHM = "sha256"

    # Compute the hex-encoded HMAC of +data+ using +secret+.
    #
    # @param secret [String] the shared signing secret (never logged)
    # @param data [String] the canonical string to sign
    # @param algorithm [String] digest name (default sha256)
    # @return [String] lowercase hex digest
    def hexdigest(secret:, data:, algorithm: DEFAULT_ALGORITHM)
      OpenSSL::HMAC.hexdigest(openssl_digest(algorithm), secret.to_s, data.to_s)
    end

    # Compute the Base64-encoded HMAC of +data+ using +secret+.
    # RFC 9421 signatures are conventionally Base64; webhook providers tend to
    # use hex. Both encodings are offered so each caller picks its wire format.
    #
    # @return [String] standard (padded) Base64 digest, no trailing newline
    def base64digest(secret:, data:, algorithm: DEFAULT_ALGORITHM)
      raw = OpenSSL::HMAC.digest(openssl_digest(algorithm), secret.to_s, data.to_s)
      Base64.strict_encode64(raw)
    end

    # Convenience signer that returns a "<scheme>=<digest>" formatted value,
    # matching the shape used by Slack/Meta style signatures
    # (e.g. "v0=abc123", "sha256=abc123").
    #
    # @param prefix [String, nil] optional scheme prefix joined with "="
    # @param encoding [Symbol] :hex (default) or :base64
    def sign(secret:, data:, algorithm: DEFAULT_ALGORITHM, prefix: nil, encoding: :hex)
      digest =
        case encoding
        when :base64 then base64digest(secret: secret, data: data, algorithm: algorithm)
        else hexdigest(secret: secret, data: data, algorithm: algorithm)
        end
      prefix.present? ? "#{prefix}=#{digest}" : digest
    end

    # Recompute the expected signature over +data+ and constant-time compare it
    # against the +provided+ signature. Returns a boolean — callers decide how
    # to react (raise, log, reject).
    #
    # @param provided [String] the signature received off the wire
    def verify(secret:, data:, provided:, algorithm: DEFAULT_ALGORITHM, prefix: nil, encoding: :hex)
      expected = sign(
        secret: secret,
        data: data,
        algorithm: algorithm,
        prefix: prefix,
        encoding: encoding
      )
      secure_compare(provided, expected)
    end

    # Constant-time string comparison that tolerates nil inputs.
    # Mirrors the helper previously private to WebhookVerificationService.
    def secure_compare(a, b)
      return false if a.nil? || b.nil?

      ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
    end

    # Resolve a caller-supplied algorithm name to the OpenSSL digest name.
    # Raises ArgumentError for unsupported algorithms so misconfiguration fails
    # loudly rather than silently downgrading.
    def openssl_digest(algorithm)
      key = algorithm.to_s.downcase.delete("-").sub(/\Ahmac/, "")
      SUPPORTED_ALGORITHMS.fetch(key) do
        raise ArgumentError, "Unsupported HMAC algorithm: #{algorithm.inspect}"
      end
    end
    private_class_method :openssl_digest
  end
end
