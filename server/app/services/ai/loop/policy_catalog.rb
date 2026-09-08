# frozen_string_literal: true

module Ai
  module Loop
    # G14 — single source of truth for the article's good-first-loop policy.
    #
    # The "Loop Engineering" doctrine is prescriptive about WHERE to let an
    # autonomous loop run: loop on CI-triage, dependency bumps, and lint/test/doc
    # fixes; keep auth, crypto, payments, billing, credentials, signing, and any
    # subjective "done" MANUAL. This catalog codifies that as data so the already-built
    # gates CONSUME it instead of each re-declaring its own list:
    #   * Ai::CodeFactory::ScopeGuardrail sources its default denylist here (G10).
    #   * Ai::Ralph::LoopReadinessService warns when a loop's declared scope overlaps
    #     the keep-manual set (G13 "scope in bounds").
    #
    # Pure / code-defined — no DB, no migration.
    class PolicyCatalog
      # FNM_CASEFOLD is load-bearing, not tidiness. Every glob below is lowercase,
      # so without it the name hints (*credential*, *secret*) only ever matched
      # snake_case Ruby paths. (The key-material hints had a second problem that
      # case-folding could not reach; they are regexes now — KEY_MATERIAL_HINTS.) Frontend files are
      # PascalCase/camelCase, which made a TSX credential panel invisible to this
      # guard: a change adding a surface that lists and deletes stored cloud
      # credentials closed unchallenged, while a snake_case controller touching the
      # same domain in the same session was blocked (IMP-a25913975485).
      #
      # It is NOT monotonically fail-closed. The same flag applies to the
      # unconditional directory globs (so **/vault/** now also matches Vault/) AND
      # to NAME_HINT_EXEMPT, which WIDENS exemption symmetrically: a file under
      # Concerns/ or Factories/ that a name hint would have caught is now exempt,
      # exactly as its lowercase twin already was. That is the intended reading —
      # a directory named Concerns/ is a concerns directory — but it means folding
      # case both gates more and exempts more. Tree-wide at the time of the change
      # this moved 20 files into keep-manual and 0 out of it.
      #
      # FNM_CASEFOLD is ASCII-only in Ruby, so this is not case-insensitivity in
      # general; a non-ASCII path still matches case-sensitively.
      FNM = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_CASEFOLD

      # KEEP-MANUAL — generic protected-path globs that must never be changed on the
      # autonomous path without human review. Directory matches use the `**/<dir>/**`
      # form so they match at any depth (FNM_PATHNAME-safe). This is the canonical
      # list of GLOBS, but not the whole rule: the key-material name hints live
      # in KEY_MATERIAL_HINTS because a glob cannot express them. The canonical
      # entry point is keep_manual_pattern, which consults both.
      # Ai::CodeFactory::ScopeGuardrail reads it through that method rather than
      # holding a copy, so the exemption semantics travel with it.
      #
      # NOTE: migrations and schema are deliberately EXCLUDED — they are far too common
      # in ordinary improvement work (every model/table change touches them) to gate.
      KEEP_MANUAL_DENYLIST = [
        # payments / billing
        "**/payments/**", "**/payment/**", "**/billing/**", "**/charges/**", "**/payouts/**",
        # auth / authz / permissions
        "**/auth/**", "**/authentication/**", "**/authorization/**",
        "**/permissions/**", "**/permission/**",
        # credentials / secrets / vault
        "**/credentials/**", "**/*credential*", "**/secrets/**", "**/*secret*", "**/vault/**",
        # signing / wallets
        # NOTE: the *signer* NAME hint is not here — see KEY_MATERIAL_HINTS.
        "**/signing/**", "**/wallet/**", "**/wallets/**",
        # key material: the NAME hints live in KEY_MATERIAL_HINTS, not here,
        # because a glob cannot express them (see that constant).
        # Rails secret files
        "**/config/credentials*", "**/config/master.key", "**/.env*"
      ].freeze

      # KEY-MATERIAL name hints. Regexes, not globs, because fnmatch can express
      # neither property this family needs.
      #
      # SEPARATOR-AGNOSTIC. api_key, api-key, apiKey and ApiKey are one concept,
      # and a frontend writes it in a case and separator style a snake_case glob
      # can never match. Case-folding alone did not fix this: "**/*api_key*"
      # needs the literal substring "api_key", which ApiKeyForm.tsx does not
      # contain at any casing (IMP-a25913975485 left this open deliberately).
      #
      # WORD-BOUNDED. The old "**/*signer*" was a substring match, so it claimed
      # every path containing "designer" — the topology-designer seed and agent
      # skeleton were keep-manual for a reason unrelated to signing keys. Fixing
      # the matcher is better than exempting those files, because the next
      # "designer" would have needed its own exemption.
      #
      # Matching runs over a normalised form (see .normalize_for_hint): every
      # separator becomes "_", camelCase and acronym boundaries become "_", and
      # the whole thing is downcased. So the patterns below only ever need to
      # describe underscore-delimited tokens.
      #
      # The keys are LABELS, deliberately not the globs these replace. Two of the
      # replaced globs would be false if pasted back into fnmatch: these match
      # the whole normalised PATH, so a directory segment counts, where
      # "**/*api_key*" under FNM_PATHNAME cannot match app/api_keys/foo.rb.
      # Gating that directory is right; reporting a glob that would not match it
      # is not, so keep_manual_pattern reports the label instead.
      #
      # The separator is OPTIONAL, so apikey and APIKEY are caught alongside
      # api_key and ApiKey. Verified over the tracked tree: making it optional
      # gates no additional file, and the trailing boundary still rejects
      # api_keyserver and ApiKeywordFilter.
      KEY_MATERIAL_HINTS = {
        "key-material name: api_key"     => /(?:\A|_)api_?keys?(?:_|\z)/,
        "key-material name: private_key" => /(?:\A|_)private_?keys?(?:_|\z)/,
        "key-material name: signer"      => /(?:\A|_)signers?(?:_|\z)/
      }.freeze

      # NAME-HINT globs — the subset of KEEP_MANUAL_DENYLIST that matches on a bare
      # WORD in the filename. These are deliberately broad and produce recurring false
      # positives on files that merely carry the word (a spec for a credential
      # validator, a display concern, a factory) without storing or handling secret
      # material. A name-hint match is therefore subject to NAME_HINT_EXEMPT below.
      # Everything else stays UNCONDITIONAL (fail-closed), even for specs and
      # concerns: the directory-form globs (**/credentials/**, **/secrets/**,
      # **/vault/**, **/signing/**, ...), the Rails secret files, and the
      # KEY_MATERIAL_HINTS regexes. That last one is a deliberate choice rather
      # than an oversight — a spec or fixture named after key material often
      # contains a real sample of it, so it is gated exactly as the globs it
      # replaced were.
      NAME_HINT_GLOBS = ["**/*credential*", "**/*secret*"].freeze

      # Structural/test shapes exempt from a NAME-HINT match only. These files do not
      # store live key material: test code, factories, and mixin concerns named after
      # the domain object they decorate. A genuine secret-storage concern belongs
      # under a gated directory (vault/ signing/ credentials/ secrets/), which remains
      # unconditionally keep-manual regardless of this list.
      NAME_HINT_EXEMPT = [
        "**/spec/**", "**/*_spec.rb", "**/test/**", "**/tests/**", "**/__tests__/**",
        "**/*.spec.*", "**/*.test.*", "**/factories/**", "**/concerns/**"
      ].freeze

      # GOOD-FIRST — the loop-friendly task categories the article calls out as the
      # right place to start an autonomous loop (low blast-radius, objective "done").
      GOOD_FIRST = %w[
        ci_triage
        dependency_bump
        lint_fix
        test_fix
        doc_update
      ].freeze

      class << self
        # @param path [String, nil]
        # @return [Boolean] true when the path falls under the keep-manual denylist.
        def keep_manual?(path)
          keep_manual_pattern(path).present?
        end

        # The glob that makes a path keep-manual, or nil. Unconditional globs win
        # first; a NAME-HINT glob (broad *credential*/*secret* filename match) only
        # counts when the file is not a structural/test shape (NAME_HINT_EXEMPT).
        # @param path [String, nil]
        # @return [String, nil] the matching denylist glob, or nil when allowed
        def keep_manual_pattern(path)
          file = path.to_s
          return nil if file.blank?

          unconditional = KEEP_MANUAL_DENYLIST - NAME_HINT_GLOBS
          hit = unconditional.find { |glob| File.fnmatch(glob, file, FNM) }
          return hit if hit

          # Key-material hints are unconditional too: they are not subject to
          # NAME_HINT_EXEMPT, so a spec or factory named after key material stays
          # gated, exactly as the globs they replace did.
          normalized = normalize_for_hint(file)
          key_hit = KEY_MATERIAL_HINTS.find { |_label, re| re.match?(normalized) }
          return key_hit.first if key_hit

          name_hit = NAME_HINT_GLOBS.find { |glob| File.fnmatch(glob, file, FNM) }
          return nil unless name_hit
          return nil if NAME_HINT_EXEMPT.any? { |glob| File.fnmatch(glob, file, FNM) }

          name_hit
        end

        # @param category [String, Symbol, nil]
        # @return [Boolean] true when the category is a sanctioned good-first loop type.
        def good_first?(category)
          return false if category.nil?

          GOOD_FIRST.include?(category.to_s)
        end

        # Normalise a path so KEY_MATERIAL_HINTS can be written as plain
        # underscore-delimited tokens.
        #
        #   frontend/src/settings/ApiKeyForm.tsx -> frontend_src_settings_api_key_form_tsx
        #   server/lib/private-key-loader.rb     -> server_lib_private_key_loader_rb
        #   .../system_topology_designer_agent.rb -> ..._system_topology_designer_agent_rb
        #
        # The third is the point: "designer" stays one token, so the underscore-
        # anchored signer pattern cannot claim it, where the old "**/*signer*"
        # substring glob did. Note the anchors are (?:\A|_) and (?:_|\z), NOT \b:
        # "_" is a word character, so \bsigner\b would fail on api_signer_x.
        #
        # Both camel rules are needed. The first splits fooBar; the second splits
        # the acronym boundary in APIKey, which the first cannot see because
        # there is no lower-to-upper transition at the K.
        #
        # @api private — public only so the spec can pin the transformation
        #   directly; it is not a general-purpose underscorize (it destroys "/"
        #   and ".") and nothing outside this class should call it.
        # @param path [String]
        # @return [String]
        def normalize_for_hint(path)
          path
            .to_s
            .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
            .gsub(/[^A-Za-z\d]+/, "_")
            .downcase
        end

        # @param paths [Array<String>]
        # @return [Array<String>] the subset of paths that are keep-manual.
        def manual_paths(paths)
          Array(paths).map(&:to_s).reject(&:blank?).select { |file| keep_manual?(file) }
        end
      end
    end
  end
end
