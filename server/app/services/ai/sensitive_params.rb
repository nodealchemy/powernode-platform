# frozen_string_literal: true

require "base64"

module Ai
  # The one place that decides what "secret" means for material riding through
  # `Ai::AutonomyGate`.
  #
  # A gated operation's params are caller-supplied and the executor replays
  # them after approval, so a single-use federation acceptance token genuinely
  # has to survive for the handshake to complete. It survives only SEALED:
  # Ai::DeferredOperation stores the masked view in its params column plus the
  # original encrypted under the ActiveRecord encryption keys, and only the
  # executor replay unseals it. The gate also mirrors params into
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
    # A PEM private key block (RSA/EC/OPENSSH/PGP and plain). The body has no key
    # beside it to judge by, so it is matched on its armor. A missing END line
    # fails closed to the end of the text, like an unclosed bracket.
    PEM_PRIVATE_KEY = /-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----|\z)/m
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
      private_key signing_key api_key api-key apikey credential
      privatekey private-key signingkey signing-key seedphrase seed-phrase
      ssh_key ssh-key sshkey tls_key tls-key tlskey kubeconfig id_rsa privkey
      client-key-data client_key_data key_pem id_ed25519 id_ecdsa
    ].freeze

    # Keys matched in FULL rather than as substrings: "pem" as a substring would
    # mask groupEmail, deepEmbedding, keepEmpty... (and trip reveal-once).
    EXACT_SECRET_KEYS = %w[pem].freeze

    # Base64 PEM armor. "-----BEGIN " can sit at any byte offset of the encoded
    # bytes (a cert-then-key bundle, a pkcs12 export whose key follows "Bag
    # Attributes" lines), and base64 encodes it three different ways depending on
    # that offset mod 3. Each needle below is the part of one encoding that does
    # not depend on the bytes around the armor: with k bytes before it, the
    # characters wholly inside the armor's bits run from ceil(8k/6) to
    # floor(8(k+11)/6) - 1. They are "LS0tLS1CRUdJTi", "0tLS0tQkVHSU4g" and
    # "tLS0tLUJFR0lOI", none using + or /, so they are the same in the URL-safe
    # alphabet. A needle only nominates a run: it is masked when its decoded bytes
    # contain a PRIVATE KEY header (a certificate-only bundle stays legible).
    BASE64_ARMOR = "-----BEGIN "
    BASE64_PEM_NEEDLES = (0..2).map do |k|
      encoded = ::Base64.strict_encode64(("\0" * k) + BASE64_ARMOR)
      encoded[((8 * k) + 5) / 6..((8 * (k + BASE64_ARMOR.bytesize)) / 6) - 1]
    end.freeze

    # A base64 run, standard or URL-safe alphabet, anywhere in a string: a
    # kubeconfig held as a JSON string, a run after a newline, a wrapped run
    # (76/64-column lines joined by real or JSON-escaped newlines, or by a single
    # space). A continuation line must look like a base64 line (16+ characters)
    # so prose after the run is not swallowed.
    BASE64_CHAR = "[A-Za-z0-9+/_-]"
    BASE64_WRAP = "(?:\\r?\\n|\\\\r\\\\n|\\\\n|[ ])"
    BASE64_RUN_SEPARATORS = /\r?\n|\\r|\\n|[ ]/

    # The needles as they appear in the TEXT: a wrap can fall anywhere inside
    # one, so at most one wrap separator is allowed between any two of its
    # characters (a wrapped line is 16+ characters, so a 14-character needle
    # crosses at most one). The scan is anchored on these and expands outward,
    # so a leaf with no armor costs one linear search and prose is never
    # enumerated word by word.
    BASE64_PEM_NEEDLE_IN_TEXT = ::Regexp.new(
      BASE64_PEM_NEEDLES.map { |needle| needle.chars.map { |c| ::Regexp.escape(c) }.join("#{BASE64_WRAP}?") }.join("|")
    )
    # A wrap splits a 14-character needle at most once, so its longer half holds
    # the needle's first or last 7 characters intact. These six literals are
    # found with a plain substring search (no regexp over the whole leaf); each
    # hit is then confirmed with BASE64_PEM_NEEDLE_IN_TEXT in a small window.
    BASE64_PEM_NEEDLE_HALVES = BASE64_PEM_NEEDLES.flat_map { |needle| [ needle[0, 7], needle[-7..] ] }.uniq.freeze
    # Widest stretch of text a needle can span: 14 characters plus one 4-byte
    # "\\r\\n" separator.
    BASE64_NEEDLE_SPAN = 18

    # The rest of a run from a needle onward.
    BASE64_RUN_TAIL = /\G#{BASE64_CHAR}*=*(?:#{BASE64_WRAP}(?=#{BASE64_CHAR}{16})#{BASE64_CHAR}+=*)*/
    # Byte classes for the walk back to a run's start.
    BASE64_BYTES = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-".bytes.to_h { |b| [ b, true ] }.freeze
    PAD_BYTE = "=".ord

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
      public_key_pem
    ].freeze

    # Metadata ABOUT a key-material field, never the material: a fingerprint,
    # type, path, file name, id or presence flag of an ssh/tls key or kubeconfig.
    # Narrow on purpose: only these subjects, so "approle_secret_id" still masks.
    SAFE_SIBLING_SUBJECTS = %w[ssh_key tls_key kubeconfig privkey id_rsa id_ed25519 id_ecdsa key_pem client_key_data].freeze
    SAFE_SIBLING_SUFFIXES = %w[fingerprint type path file id present].freeze
    # The suffixes that vouch for the NAME but not the value: "kubeconfig_file"
    # can just as well hold the file's contents. Kept legible only when the value
    # looks like a filesystem path (mask_path_siblings).
    PATH_SIBLING_SUFFIXES = %w[path file].freeze
    # One line, no whitespace, rooted (/, ~, ./ or a Windows drive).
    FILESYSTEM_PATH = %r{\A(?:/|~|\./|[A-Za-z]:\\)\S*\z}
    # Or a bare relative file name ("admin.conf", "id_rsa"), at most 255
    # characters, ...
    BARE_FILENAME = /\A[\w.-]{1,255}\z/
    # ... unless it has a base64 key's shape: 16+ characters of the base64
    # alphabet with no dot (a one-line key, a token). A file name of that shape
    # is masked: over-masking, never a leak.
    BASE64_KEY_SHAPE = /\A[A-Za-z0-9+\/_=-]{16,}\z/

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

        mask_pem_leaves(mask_path_siblings(parameter_filter.filter(value)))
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
      def filter_text(text, truncate: true)
        return text if text.nil?

        # Valid UTF-8 before any regexp touches it: an exception message can
        # carry invalid bytes (a parser quoting a binary body), and a regexp
        # over those raises rather than masking.
        text = text.to_s.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace).scrub
        cut = truncate && text.length > TEXT_SCAN_WINDOW
        text = drop_cut_token(text[0, TEXT_SCAN_WINDOW]) if cut

        text = mask_base64_pem(text.gsub(PEM_PRIVATE_KEY, MASK))
        masked = mask_keyed_values(text.gsub(URL_USERINFO) { "#{::Regexp.last_match(1)}#{MASK}@" })
        masked = masked.gsub(BEARER) { "#{::Regexp.last_match(1)}#{MASK}" }
        masked << "..." if cut
        truncate ? masked.truncate(TEXT_LIMIT) : masked
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

      # Memoised inside a `batch`, like the compiled filter: a result envelope or
      # a scrub batch text-filters one string leaf at a time, and each used to
      # read the setting again.
      def key_patterns
        memo = ::ActiveSupport::IsolatedExecutionState[MEMO_KEY]
        return DEFAULT_KEY_PATTERNS + configured_key_patterns unless memo

        memo[:key_patterns] ||= DEFAULT_KEY_PATTERNS + configured_key_patterns
      end

      private

      # A PEM private key block has no key beside it to judge by, so every
      # string leaf is scanned for its armor (the hash twin of filter_text's
      # PEM pass).
      def mask_pem_leaves(node)
        case node
        when ::Hash then node.each_with_object(node.class.new) { |(k, v), out| out[k] = mask_pem_leaves(v) }
        when ::Array then node.map { |v| mask_pem_leaves(v) }
        when ::String then mask_pem_string(node)
        else node
        end
      end

      def mask_pem_string(string)
        masked = string.include?("PRIVATE KEY") ? string.gsub(PEM_PRIVATE_KEY, MASK) : string
        mask_base64_pem(masked)
      end

      # A *_path / *_file sibling of a key-material name survives the key filter
      # (the sibling veto) on the strength of its name alone. Here its value has
      # to agree: anything but a filesystem path or a bare file name is masked.
      def mask_path_siblings(node)
        case node
        when ::Hash
          node.each_with_object(node.class.new) do |(key, value), out|
            out[key] = path_sibling_key?(key) && !filesystem_path?(value) ? MASK : mask_path_siblings(value)
          end
        when ::Array then node.map { |value| mask_path_siblings(value) }
        else node
        end
      end

      def path_sibling_key?(key)
        @path_sibling_key ||= begin
          subjects = SAFE_SIBLING_SUBJECTS.map { |w| ascii_flexible(w) }.join("|")
          suffixes = PATH_SIBLING_SUFFIXES.map { |w| ascii_flexible(w) }.join("|")
          ::Regexp.new("\\A(?!#{has_prefix})(?-i:.*(?:#{subjects})[-_]?(?:#{suffixes}))\\z", ::Regexp::MULTILINE)
        end
        @path_sibling_key.match?(key.to_s)
      end

      def filesystem_path?(value)
        return false unless value.is_a?(::String)

        FILESYSTEM_PATH.match?(value) || (BARE_FILENAME.match?(value) && !BASE64_KEY_SHAPE.match?(value))
      end

      # True when the base64 +run+ decodes to bytes holding a PEM PRIVATE KEY
      # header, anywhere in them. The run is decoded at each of the four
      # character offsets (a run glued to a word need not start on a quantum),
      # then once more in the URL-safe alphabet.
      #
      # Why the URL-safe retry: the lenient standard decode SKIPS a - or _,
      # misaligning what follows by one character per skip. A skip well before
      # the armor is harmless, one of the four offsets realigns it (ASCII text
      # does encode to 62/63: "???" is "Pz8_" URL-safe). The header's own
      # encoding never holds one either (dashes, spaces, digits and capitals have
      # no five 1-bits in a row). What breaks is a skip in the quantum the armor
      # starts in: a byte of 0xF8 or above just before "-----" (binary or Latin-1
      # text, never ASCII) encodes to 62/63, and the realigned decode then starts
      # past the first dashes. Only the URL-safe decode reads that header.
      def base64_pem?(run)
        flat = run.gsub(BASE64_RUN_SEPARATORS, "")
        candidates = [ flat ]
        candidates << flat.tr("-_", "+/") if flat.match?(/[-_]/)
        candidates.any? do |candidate|
          (0..3).any? { |offset| ::Base64.decode64(candidate[offset..].to_s).match?(/-----BEGIN [A-Z0-9 ]*PRIVATE KEY/) }
        end
      rescue ArgumentError
        false
      end

      def mask_base64_pem(text)
        return text unless BASE64_PEM_NEEDLE_HALVES.any? { |half| text.include?(half) }

        # Byte offsets on a binary copy: O(1) indexing whatever the text's
        # encoding, and a run is ASCII, so its bounds are character bounds too.
        bin = text.b
        runs = base64_pem_runs(bin)
        return text if runs.empty?

        out = +""
        pos = 0
        runs.each do |from, to|
          out << text.byteslice(pos...from) << MASK
          pos = to
        end
        out << text.byteslice(pos..)
      end

      # [start, end) byte offsets of every run that carries an armor needle (a
      # wrap may split the needle) and decodes to a PRIVATE KEY header, in order.
      def base64_pem_runs(bin)
        runs = []
        pos = 0
        hits = {}
        while (needle = next_needle(bin, pos, hits))
          from = base64_run_start(bin, needle.first)
          to = bin.match(BASE64_RUN_TAIL, needle.first).end(0)
          runs << [ from, to ] if base64_pem?(bin.byteslice(from...to))
          pos = [ to, needle.last ].max
        end
        runs
      end

      # [start, end) of the first needle (wrap-split or not) at or after +pos+,
      # or nil. Driven by substring hits on the needle halves (+hits+ caches
      # each half's next offset, :none once it has none left), each confirmed in
      # a window just wide enough to hold a needle that contains it.
      def next_needle(bin, pos, hits)
        loop do
          BASE64_PEM_NEEDLE_HALVES.each do |half|
            next if hits[half] == :none || (hits[half] && hits[half] >= pos)

            hits[half] = bin.index(half, pos) || :none
          end
          hit = hits.values.grep(Integer).min
          return nil unless hit

          from = [ hit - BASE64_NEEDLE_SPAN, pos ].max
          window = bin.byteslice(from, (hit - from) + (2 * BASE64_NEEDLE_SPAN))
          match = BASE64_PEM_NEEDLE_IN_TEXT.match(window)
          return [ from + match.begin(0), from + match.end(0) ] if match

          pos = hit + 1
        end
      end

      # Walks back from +index+ to the start of its run: the base64 bytes glued
      # to it, then each whole wrapped line (16+ characters, optional padding,
      # not glued to a word) before a wrap separator.
      def base64_run_start(bin, index)
        start = skip_base64_back(bin, index)
        loop do
          sep = wrap_before(bin, start)
          break unless sep

          line_end = sep
          line_end -= 1 while line_end.positive? && bin.getbyte(line_end - 1) == PAD_BYTE
          line_start = skip_base64_back(bin, line_end)
          break if line_end - line_start < 16
          break if line_start.positive? && (BASE64_BYTES[bin.getbyte(line_start - 1)] || bin.getbyte(line_start - 1) == PAD_BYTE)

          start = line_start
        end
        start
      end

      def skip_base64_back(bin, index)
        index -= 1 while index.positive? && BASE64_BYTES[bin.getbyte(index - 1)]
        index
      end

      # Start of the wrap separator ending at +index+, or nil.
      def wrap_before(bin, index)
        [ "\\r\\n", "\r\n", "\\n", "\n", " " ].each do |sep|
          from = index - sep.bytesize
          return from if from >= 0 && bin.byteslice(from, sep.bytesize) == sep
        end
        nil
      end

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
        key = keyed_value_regexp
        out = +""
        pos = 0
        while (match = key.match(text, pos))
          out << text[pos...match.end(0)] << MASK
          pos = value_end(text, match.end(0))
        end
        out << text[pos..]
      end

      # Memoised inside a `batch` with the patterns it is built from.
      def keyed_value_regexp
        memo = ::ActiveSupport::IsolatedExecutionState[MEMO_KEY]
        return build_keyed_value_regexp unless memo

        memo[:keyed_value_regexp] ||= build_keyed_value_regexp
      end

      def build_keyed_value_regexp
        keys = (key_patterns + TEXT_EXTRA_KEYS).filter_map { |pattern| flexible(pattern) }.join("|")
        /(?:#{keys})[\w.-]*["']?\s*(?:=>|[:=])\s*/i
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

        exact = EXACT_SECRET_KEYS.map { |key| ::Regexp.escape(key) }.join("|")
        ::Regexp.new("\\A(?!#{allowlist_veto}\\z)(?!#{sibling_veto}\\z)(?:.*(?:#{alternation(patterns)})|(?:#{exact})\\z)",
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
        # Separator- and camelCase-insensitive like the patterns (publicKeyPem is
        # as safe as public_key_pem), ASCII-only so folding cannot satisfy it.
        "(?-i:(?:#{SAFE_KEY_ALLOWLIST.map { |key| ascii_flexible(key) }.join('|')}))"
      end

      def alternation(patterns)
        patterns.filter_map { |pattern| flexible(pattern) }.join("|")
      end

      # A key pattern matched case-insensitively with its - and _ separators
      # optional and interchangeable: private_key covers privateKey, PrivateKey,
      # private-key and privatekey. A dotted (path) pattern is taken literally.
      # Blank parts are dropped ("a--b" is "a_b"), and a pattern that is only
      # separators yields nil: its empty alternative would match every key.
      def flexible(pattern)
        return ::Regexp.escape(pattern) if pattern.include?(".")

        parts = pattern.split(/[-_]/).reject(&:blank?)
        return nil if parts.empty?

        parts.map { |part| ::Regexp.escape(part) }.join("[-_]?")
      end

      # ASCII-only case-insensitive source for +word+ (separators optional), inside
      # an (?-i:) group: byte-exact modulo ASCII case, so Unicode folding (U+212A)
      # cannot satisfy a veto.
      def ascii_flexible(word)
        word.split(/[-_]/).map do |part|
          part.each_char.map { |c| c.match?(/[a-z]/i) ? "[#{c.downcase}#{c.upcase}]" : ::Regexp.escape(c) }.join
        end.join("[-_]?")
      end

      def sibling_veto
        subjects = SAFE_SIBLING_SUBJECTS.map { |w| ascii_flexible(w) }.join("|")
        suffixes = SAFE_SIBLING_SUFFIXES.map { |w| ascii_flexible(w) }.join("|")
        "(?-i:(?:.*(?:#{subjects})[-_]?(?:#{suffixes})|#{has_prefix}.*(?:#{subjects})))"
      end

      # A presence flag's "has": followed by a separator (has_, HAS-) or by a
      # camelCase boundary (hasKubeconfig, HasSshKey). Unanchored, it vouched for
      # hashicorp_ssh_key, hasura_kubeconfig and haskeyKubeconfig. ASCII-exact.
      def has_prefix
        "(?-i:[hH][aA][sS][-_]|[hH]as(?=[A-Z]))"
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
