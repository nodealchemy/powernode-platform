# frozen_string_literal: true

module Ai
  # The one place that decides what "secret" means for material riding through
  # `Ai::AutonomyGate`.
  #
  # A gated operation's params are caller-supplied and stored verbatim: the
  # executor replays them after approval, so a single-use federation acceptance
  # token genuinely has to survive at rest for the handshake to complete. What
  # must not survive is the COPY. The gate mirrors params into
  # `Ai::ApprovalRequest#request_data`, and four read endpoints serialize that
  # copy — or the operation's own params — to an audience defined by the
  # approval permissions rather than by whatever permission authorised the
  # original call. For federation acceptance that is `ai.agents.read` (the
  # autonomy approvals reads clear on `validate_permissions` alone) against a
  # token minted under `system.sdwan.federation.manage`.
  #
  # Deliberately key-pattern based and core-generic. Core must not know which
  # extension mints which secret, and a pattern match means a NEW producer is
  # covered the moment its param is named for what it is — the REST federation
  # acceptance path inherits this from the MCP one without either knowing it
  # exists.
  #
  # Matching is substring + case-insensitive, delegated to
  # ActiveSupport::ParameterFilter: the same mechanism Rails uses for log
  # filtering, pointed at an API surface. The pattern LIST is deliberately not
  # Rails' own `filter_parameters` — that list is tuned for logs and includes
  # :email and :certificate, and blanking those on an approval card costs the
  # approver context needed to make the decision. Over-redaction on a card an
  # operator must act on is its own failure, distinct from a leak.
  class SensitiveParams
    MASK = "[FILTERED]"

    # Names for secret material, not for anything merely private. Matched as
    # substrings, so "token" covers acceptance_token and
    # acceptance_token_plaintext alike.
    DEFAULT_KEY_PATTERNS = %w[
      token secret password passphrase mnemonic seed_phrase
      private_key signing_key api_key credential
    ].freeze

    # Deployment-specific additions (JSON array of strings). EXTENDS the
    # defaults rather than replacing them, so a misconfigured setting cannot
    # unmask the baseline.
    SETTING_KEY = "ai_sensitive_param_keys"

    class << self
      # Deep copy with every value under a secret-looking key replaced by MASK.
      # Nested hashes and arrays are traversed; non-Hash input is returned
      # unchanged, since a bare scalar carries no key to judge it by.
      def filter(value)
        return value unless value.is_a?(Hash)

        ::ActiveSupport::ParameterFilter.new(key_patterns, mask: MASK).filter(value)
      end

      def key_patterns
        DEFAULT_KEY_PATTERNS + configured_key_patterns
      end

      private

      # Fails open to the defaults rather than raising: this runs inside the
      # gate's write path and inside serializers, and an unreadable setting must
      # not take an approval surface down. The baseline still applies.
      def configured_key_patterns
        Array(::SiteSetting.get(SETTING_KEY)).map(&:to_s).select(&:present?)
      rescue StandardError => e
        Rails.logger.warn("[Ai::SensitiveParams] #{SETTING_KEY} unreadable, using defaults: #{e.message}")
        []
      end
    end
  end
end
