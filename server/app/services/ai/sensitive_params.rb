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
  #
  # SAFE_KEY_ALLOWLIST is the exception carved out of the substring rule for
  # exactly that reason, and it is checked FIRST (IMP-77645b94151e).
  class SensitiveParams
    MASK = "[FILTERED]"

    # Names for secret material, not for anything merely private. Matched as
    # substrings, so "token" covers acceptance_token and
    # acceptance_token_plaintext alike.
    DEFAULT_KEY_PATTERNS = %w[
      token secret password passphrase mnemonic seed_phrase
      private_key signing_key api_key credential
    ].freeze

    # Keys that a pattern WOULD match and that provably hold no material —
    # checked before every pattern, including the deployment-configured ones, so
    # a deployment can widen the masked set but cannot re-mask a key core has
    # declared safe. Each entry is a full key name matched EXACTLY (the patterns
    # stay substring): a decorated variant is a different key nobody has vouched
    # for, and it keeps failing closed.
    #
    # All three ride federation propose. The first two are control flags the
    # approver needs in order to judge the request at all; the third is the only
    # thing on the persisted result telling anyone how long the handshake has,
    # and it is collateral damage from sharing "token" with the mint beside it
    # (Sdwan::Executors::ProposeFederationPeer).
    #
    # BOUNDARY: exact-match, so this cannot cover an identifier whose ENTITY is
    # named for a secret (a gated `dns_credential_id` would still mask). None
    # reaches this filter today; widening the rule to "any _id survives" was
    # rejected — over-redaction is visible on the card, a leak is not, and that
    # is the polarity to keep.
    SAFE_KEY_ALLOWLIST = %w[
      generate_token
      token_ttl_seconds
      acceptance_token_expires_at
    ].freeze

    # Deployment-specific additions (JSON array of strings). EXTENDS the
    # defaults rather than replacing them, so a misconfigured setting cannot
    # unmask the baseline.
    SETTING_KEY = "ai_sensitive_param_keys"

    # Where an open `batch` parks its compiled filter. Execution-state scoped,
    # never a class-level ivar: two requests on one Puma thread must not share a
    # resolution.
    MEMO_KEY = :ai_sensitive_params_batch

    class << self
      # Deep copy with every value under a secret-looking key replaced by MASK,
      # unless the key is allowlisted. Nested hashes and arrays are traversed;
      # non-Hash input is returned unchanged, since a bare scalar carries no key
      # to judge it by.
      def filter(value)
        return value unless value.is_a?(Hash)

        parameter_filter.filter(value)
      end

      # Resolve the pattern set and compile the matcher ONCE for the duration of
      # the block. Serializing an approvals queue filters one payload per row
      # and used to pay for a SiteSetting lookup and a regexp compilation on
      # every one of them.
      #
      # Scoped to the block and restored in `ensure` — deliberately NOT a
      # process-wide or cross-request cache, so a setting written between two
      # blocks is visible to the second one. Nested blocks reuse the outer
      # resolution rather than starting a second.
      def batch
        outer = ::ActiveSupport::IsolatedExecutionState[MEMO_KEY]
        ::ActiveSupport::IsolatedExecutionState[MEMO_KEY] = outer || {}
        yield
      ensure
        ::ActiveSupport::IsolatedExecutionState[MEMO_KEY] = outer
      end

      def key_patterns
        DEFAULT_KEY_PATTERNS + configured_key_patterns
      end

      private

      # Lazy inside a batch: a block that filters nothing costs no lookup.
      def parameter_filter
        memo = ::ActiveSupport::IsolatedExecutionState[MEMO_KEY]
        return build_parameter_filter unless memo

        memo[:filter] ||= build_parameter_filter
      end

      def build_parameter_filter
        ::ActiveSupport::ParameterFilter.new([ key_matcher ], mask: MASK)
      end

      # One regexp rather than ParameterFilter's own string list, because that
      # list is a flat OR with no way to express precedence. The allowlist is a
      # negative lookahead anchored to the WHOLE key, so it is decided at
      # position 0 — before the substring alternation is ever tried.
      #
      # MULTILINE so `.` spans a newline: a key like "x\ntoken" must not slip
      # past the alternation on the strength of a line break.
      def key_matcher
        allowed = SAFE_KEY_ALLOWLIST.map { |key| ::Regexp.escape(key) }.join("|")
        patterns = key_patterns.map { |pattern| ::Regexp.escape(pattern) }.join("|")

        ::Regexp.new("\\A(?!(?:#{allowed})\\z)(?:.*(?:#{patterns}))",
                     ::Regexp::IGNORECASE | ::Regexp::MULTILINE)
      end

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
