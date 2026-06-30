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
          file = path.to_s
          return false if file.blank?

          KEEP_MANUAL_DENYLIST.any? { |glob| File.fnmatch(glob, file, FNM) }
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
