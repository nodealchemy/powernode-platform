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

    # Longest free text `filter_text` returns. An exception message is the
    # caller's to bound: a driver error can quote a whole failing row.
    TEXT_LIMIT = 500

    # How much of a text `filter_text` will scan. The output is cut to
    # TEXT_LIMIT, so nothing past this can be emitted, and an exception column
    # is unbounded. Everything emitted was scanned; the cut is marked with an
    # ellipsis, after dropping the token the cut runs through.
    TEXT_SCAN_WINDOW = 32 * 1024

    # Key names `filter_text` masks beyond key_patterns: a header, not a hash
    # key, so it never reaches `filter`.
    TEXT_EXTRA_KEYS = %w[authorization].freeze

    URL_USERINFO = %r{([a-z][a-z0-9+.-]*://)[^\s/?#]*@}i
    BEARER = /\b(Bearer\s+)\S+/i
    # A `, key=`, `; key:` or `& key=>` that ends an unquoted value.
    VALUE_DELIMITER = /[,;&]\s*[\w.-]+["']?\s*(?:=>|[:=])/
    VALUE_STOP = ::Regexp.union(/[\r\n]/, VALUE_DELIMITER)
    BRACKET_PAIRS = { "[" => "]", "{" => "}", "(" => ")" }.freeze

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
    #
    # AuditLog metadata is filtered here since IMP-4fdae24c24a3. tokens_revoked is
    # a COUNT an audit row records for an OAuth application revocation, and
    # api_key_name is an ApiKey's display name: once the key row is deleted it is
    # the only readable record of which key an audit row was about.
    SAFE_KEY_ALLOWLIST = %w[
      generate_token
      token_ttl_seconds
      acceptance_token_expires_at
      tokens_revoked
      api_key_name
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

      # The free-text counterpart of `filter`, for a column that holds raw
      # exception text ("Class: message") rather than a hash: an executor's
      # error can quote the very params `filter` exists to mask, as
      # `{"acceptance_token"=>"..."}`, `password=...` or an Authorization
      # header. Scans for a secret-named key (key_patterns plus TEXT_EXTRA_KEYS)
      # followed by `=`, `:` or `=>`, then masks the WHOLE value after it:
      #
      #   a quoted value           to its closing quote, honouring backslash escapes;
      #   a [ { ( value            to its MATCHING bracket, so every element of a
      #                            list or hash goes, quotes and nesting respected;
      #   any other value          to the end of the line, or the next
      #                            `, key=` / `; key:` / `& key=` delimiter.
      #
      # It FAILS CLOSED: a quote or bracket that is never closed, or a bracket
      # closed by the wrong kind, masks everything to the end of the text rather
      # than guessing where the value stopped. Over-masking is visible on the
      # card; a leak is not. The URL userinfo of `scheme://user:pw@host` and a
      # bare Bearer credential are masked wherever they appear. Only the first
      # TEXT_SCAN_WINDOW characters are scanned, and the result is truncated to
      # TEXT_LIMIT; nil passes through, and invalid UTF-8 is replaced rather
      # than raised on.
      #
      # Still best-effort: prose cannot be judged by a key, so a secret quoted
      # with no key beside it survives, and truncation is the only bound on it.
      # The allowlist is deliberately NOT consulted (a key it vouches for masks
      # here).
      def filter_text(text)
        return text if text.nil?

        # Valid UTF-8 before any regexp touches it: an exception message can
        # carry invalid bytes (a parser quoting a binary body), and a regexp
        # over those raises rather than masking.
        text = text.to_s.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace).scrub
        cut = text.length > TEXT_SCAN_WINDOW
        text = drop_cut_token(text[0, TEXT_SCAN_WINDOW]) if cut

        masked = mask_keyed_values(text.gsub(URL_USERINFO) { "#{::Regexp.last_match(1)}#{MASK}@" })
        masked = masked.gsub(BEARER) { "#{::Regexp.last_match(1)}#{MASK}" }
        masked << "..." if cut
        masked.truncate(TEXT_LIMIT)
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

      # Everything after the last whitespace of a window cut off mid-text. The
      # token the cut runs through has lost whatever gave it away (a URL its
      # `@`, a value its closing quote), so the masking rules cannot recognise
      # its head, and masking an earlier value shrinks the text enough to pull
      # that head into the output. No whitespace at all leaves nothing: the whole
      # window is one unbounded token.
      def drop_cut_token(window)
        boundary = window.rindex(/\s/)
        boundary ? window[0..boundary] : ""
      end

      # Rewrites every secret-keyed value in `text` to MASK, keeping the key and
      # its separator. Scanning resumes after each masked value, so a key nested
      # inside one is consumed with it.
      def mask_keyed_values(text)
        keys = (key_patterns + TEXT_EXTRA_KEYS).map { |pattern| ::Regexp.escape(pattern) }.join("|")
        key = /(?:#{keys})[\w.-]*["']?\s*(?:=>|[:=])\s*/i
        out = +""
        pos = 0
        while (match = key.match(text, pos))
          out << text[pos...match.end(0)] << MASK
          pos = value_end(text, match.end(0))
        end
        out << text[pos..]
      end

      # Index just past the value that starts at `start`; text.length when it
      # cannot be bounded (fail closed).
      def value_end(text, start)
        first = text[start]
        return quoted_end(text, start) if first == '"' || first == "'"
        return bracket_end(text, start) if BRACKET_PAIRS.key?(first)

        # ONE search for both stops: two separate ones each scan to the end of
        # the text when their stop is absent, which made this quadratic.
        text.index(VALUE_STOP, start) || text.length
      end

      # Just past the closing quote of the string opening at `start`;
      # text.length when there is none.
      def quoted_end(text, start)
        quote = text[start]
        i = start + 1
        while i < text.length
          case text[i]
          when "\\" then i += 1
          when quote then return i + 1
          end
          i += 1
        end
        text.length
      end

      # Just past the bracket matching the one at `start`. Quoted strings inside
      # are skipped whole, so a bracket in a string does not count.
      def bracket_end(text, start)
        stack = []
        i = start
        while i < text.length
          char = text[i]
          if char == '"' || char == "'"
            i = quoted_end(text, i)
            next
          elsif BRACKET_PAIRS.key?(char)
            stack << BRACKET_PAIRS[char]
          elsif BRACKET_PAIRS.value?(char)
            return text.length unless stack.pop == char
            return i + 1 if stack.empty?
          end
          i += 1
        end
        text.length
      end

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
