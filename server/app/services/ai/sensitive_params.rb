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
    # NOT retroactive for :result. Ai::DeferredOperation#execute_now! filters at
    # WRITE, so rows completed before this landed keep a masked expiry forever —
    # unlike request_data, which the read surfaces re-filter every time.
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

    # Where an open `batch` parks its compiled filter. The execution state is
    # THREAD-scoped and nothing clears it between requests, so the `ensure` in
    # `batch` is the only thing keeping this from becoming a process-lifetime
    # cache — an early return added to `batch` later would not be safe.
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

      # A pattern containing a dot means dot-notation to ParameterFilter: it is
      # routed to @deep_regexps and matched against "parent.key" instead of the
      # bare key. That routing is decided per FILTER, by whether the filter's
      # own source contains a "\.", so fusing a dotted deployment pattern into
      # the same regexp as everything else would drag the whole matcher — the
      # allowlist included — onto the deep path, where the allowlist's whole-key
      # anchor can never match a nested key again. One dotted setting value
      # would have silently re-masked every allowlisted key nested under
      # `attributes`, which is exactly the shape this class exists to keep
      # legible. Keep the two halves in separate regexps so each is routed on
      # its own merits.
      def build_parameter_filter
        dotted, plain = key_patterns.partition { |pattern| pattern.include?(".") }

        ::ActiveSupport::ParameterFilter.new(
          [ key_matcher(plain), *deep_matchers(dotted) ].compact, mask: MASK
        )
      end

      # One regexp rather than ParameterFilter's own string list, because that
      # list is a flat OR with no way to express precedence. The allowlist is a
      # negative lookahead anchored to the WHOLE key, so it is decided at
      # position 0 — before the substring alternation is ever tried.
      #
      # The allowlist alternation is wrapped in (?-i:...) over per-character
      # classes rather than left to the enclosing /i: Onigmo's Unicode folding
      # maps U+212A KELVIN SIGN onto "k", so an /i lookahead would let
      # a key carrying U+212A in the "k" position satisfy an "EXACT" allowlist
      # entry, vetoing the masking of a key the substring list would otherwise
      # have caught. The veto has to be byte-exact modulo ASCII case; the
      # PATTERN half stays Unicode-case-insensitive, which is the direction
      # that fails closed.
      #
      # MULTILINE so `.` spans a newline: a key like "x\ntoken" must not slip
      # past the alternation on the strength of a line break.
      def key_matcher(patterns)
        return nil if patterns.empty?

        ::Regexp.new("\\A(?!#{allowlist_veto}\\z)(?:.*(?:#{alternation(patterns)}))",
                     ::Regexp::IGNORECASE | ::Regexp::MULTILINE)
      end

      # Dot-notation patterns, matched against the full "parent.key" path. The
      # veto is anchored to the LEAF segment, so the allowlist keeps its meaning
      # on this path too: a deployment can widen the masked set, it cannot
      # re-mask a key core has declared safe.
      def deep_matchers(patterns)
        return [] if patterns.empty?

        veto = "(?!(?:.*\\.)?#{allowlist_veto}\\z)"
        patterns.map do |pattern|
          ::Regexp.new("\\A#{veto}(?:.*#{::Regexp.escape(pattern)})",
                       ::Regexp::IGNORECASE | ::Regexp::MULTILINE)
        end
      end

      def allowlist_veto
        entries = SAFE_KEY_ALLOWLIST.map do |key|
          key.each_char.map do |char|
            char.match?(/[a-z]/i) ? "[#{char.downcase}#{char.upcase}]" : ::Regexp.escape(char)
          end.join
        end

        "(?-i:(?:#{entries.join('|')}))"
      end

      def alternation(patterns)
        patterns.map { |pattern| ::Regexp.escape(pattern) }.join("|")
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
