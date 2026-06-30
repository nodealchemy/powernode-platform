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
      # be changed on the autonomous path without human review. Sourced from the single
      # policy catalog (G14) so there is ONE canonical list — see
      # Ai::Loop::PolicyCatalog::KEEP_MANUAL_DENYLIST for the globs + rationale.
      DEFAULT_DENYLIST = Ai::Loop::PolicyCatalog::KEEP_MANUAL_DENYLIST

      # Convenience: evaluate executor-reported changed files against a loop's
      # guardrail (its risk_contract + configuration["scope_guardrail"]) and return
      # the VIOLATION result hash, or nil when clean / no files. The single seam
      # shared by every enforcement path — the dev-loop pull path, the platform
      # executor path, and (with loop_record nil) the land path, which only has the
      # default protected-path denylist (no per-loop contract/config).
      # @param files [Array<String>] changed file paths
      # @param loop_record [Ai::RalphLoop, nil]
      # @return [Hash, nil] the evaluate() result when blocked, else nil
      def self.violation_for(files, loop_record: nil)
        list = Array(files).map(&:to_s).reject(&:blank?)
        return nil if list.empty?

        result = new(
          risk_contract: loop_record&.try(:risk_contract),
          config: (loop_record.respond_to?(:configuration) ? loop_record.configuration : nil).to_h["scope_guardrail"]
        ).evaluate(list)
        result[:allowed] ? nil : result
      end

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
