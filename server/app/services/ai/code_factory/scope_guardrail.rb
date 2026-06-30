# frozen_string_literal: true

module Ai
  module CodeFactory
    # Enforces loop scope guardrails: blocks an autonomous change from touching
    # protected paths (payments / auth / crypto / secrets) or a critical-tier file,
    # instead of silently accepting it. Pure — performs no DB writes; callers decide
    # how to act on the verdict (the dev-loop remaps a violating pass to a human-gated
    # block). Reuses Ai::CodeFactory::RiskContract tiering for the critical-tier check.
    class ScopeGuardrail
      FNM = File::FNM_PATHNAME | File::FNM_DOTMATCH

      # The article's "keep-manual" set: generic protected-path globs that should never
      # be changed on the autonomous path without human review. Directory matches use the
      # `**/<dir>/**` form so they match at any depth (FNM_PATHNAME-safe).
      #
      # NOTE: migrations and schema are deliberately EXCLUDED — they are far too common in
      # ordinary improvement work (every model/table change touches them) to gate here.
      DEFAULT_DENYLIST = [
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

      # @param risk_contract [Ai::CodeFactory::RiskContract, nil] used for critical-tier detection
      # @param config [Hash, nil] the loop's configuration["scope_guardrail"]; optional
      #   "deny" (extra globs) and "allow" (override globs that exempt a path entirely)
      def initialize(risk_contract: nil, config: nil)
        @risk_contract = risk_contract
        @config = config.is_a?(Hash) ? config : {}
      end

      # @param paths [Array<String>] files changed by the iteration (executor-reported)
      # @return [Hash] { allowed:, violations:, highest_tier:, summary: }
      def evaluate(paths)
        files = Array(paths).map(&:to_s).reject(&:blank?)
        return result(true, [], nil) if files.empty?

        allow_globs = Array(@config["allow"])
        deny_globs  = DEFAULT_DENYLIST + Array(@config["deny"])

        # Allow globs override everything — exempt those files from both checks.
        considered = files.reject { |f| matches_any?(f, allow_globs) }

        violations = []
        flagged = {}

        # Protected-path denylist.
        considered.each do |file|
          pattern = matching_pattern(file, deny_globs)
          next unless pattern

          violations << { file: file, reason: "protected path (#{pattern})" }
          flagged[file] = true
        end

        # Critical-tier (risk contract) check — only when a contract is present and the
        # highest tier across the considered files is "critical".
        highest_tier = nil
        if @risk_contract
          top = @risk_contract.highest_tier_for_files(considered)
          if top && top["tier"] == "critical"
            highest_tier = "critical"
            considered.each do |file|
              next if flagged[file] # don't double-add a denylist hit

              tier = @risk_contract.tier_for_file(file)
              next unless tier && tier["tier"] == "critical"

              violations << { file: file, reason: "critical-tier change (risk contract)" }
              flagged[file] = true
            end
          end
        end

        result(violations.empty?, violations, highest_tier)
      end

      private

      def result(allowed, violations, highest_tier)
        summary =
          if allowed
            nil
          else
            "blocked #{violations.size} file(s): #{violations.map { |v| v[:file] }.join(', ')}"
          end
        { allowed: allowed, violations: violations, highest_tier: highest_tier, summary: summary }
      end

      def matches_any?(file, globs)
        Array(globs).any? { |glob| File.fnmatch(glob.to_s, file, FNM) }
      end

      def matching_pattern(file, globs)
        Array(globs).find { |glob| File.fnmatch(glob.to_s, file, FNM) }
      end
    end
  end
end
