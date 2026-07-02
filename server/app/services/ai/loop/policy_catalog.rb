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
      FNM = File::FNM_PATHNAME | File::FNM_DOTMATCH

      # KEEP-MANUAL — generic protected-path globs that must never be changed on the
      # autonomous path without human review. Directory matches use the `**/<dir>/**`
      # form so they match at any depth (FNM_PATHNAME-safe). This is the canonical
      # list; ScopeGuardrail's DEFAULT_DENYLIST is derived from it.
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
        "**/signing/**", "**/*signer*", "**/wallet/**", "**/wallets/**",
        # key material
        "**/*private_key*", "**/*api_key*",
        # Rails secret files
        "**/config/credentials*", "**/config/master.key", "**/.env*"
      ].freeze

      # NAME-HINT globs — the subset of KEEP_MANUAL_DENYLIST that matches on a bare
      # WORD in the filename. These are deliberately broad and produce recurring false
      # positives on files that merely carry the word (a spec for a credential
      # validator, a display concern, a factory) without storing or handling secret
      # material. A name-hint match is therefore subject to NAME_HINT_EXEMPT below.
      # Everything else in the denylist — directory-form globs (**/credentials/**,
      # **/secrets/**, **/vault/**, **/signing/**, ...), Rails secret files, and the
      # key-material name globs (*private_key* / *api_key* / *signer*) — stays
      # UNCONDITIONAL (fail-closed), even for specs and concerns.
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

        # @param paths [Array<String>]
        # @return [Array<String>] the subset of paths that are keep-manual.
        def manual_paths(paths)
          Array(paths).map(&:to_s).reject(&:blank?).select { |file| keep_manual?(file) }
        end
      end
    end
  end
end
