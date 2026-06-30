# frozen_string_literal: true

module Ai
  class Skill
    # Static content / prompt-injection scanner for skill payloads
    # (system_prompt, command names + descriptions, recipe step text). Runs at
    # create / update / attach so operator- or community-supplied skill content
    # is vetted before it is persisted or bound to an agent.
    #
    # Pure analysis — performs NO database writes and NEVER echoes the matched
    # content. Findings carry only the marker category and the (truncated)
    # detector source, so a skill that tries to smuggle a secret cannot leak it
    # through a finding, a log line, or an API response.
    #
    # Reuses the platform's canonical injection corpus
    # (Ai::Security::AgentAnomalyDetectionService) rather than maintaining a
    # parallel list, plus skill-specific markers for secret exfiltration and
    # tool / permission directive overrides.
    class ContentScanService
      INJECTION_PATTERNS = (
        Ai::Security::AgentAnomalyDetectionService::PROMPT_INJECTION_PATTERNS +
        Ai::Security::AgentAnomalyDetectionService::ROLE_HIJACK_PATTERNS
      ).freeze

      # Attempts to make a skill exfiltrate platform secrets / key material.
      SECRET_EXFIL_PATTERNS = [
        /\b(print|output|echo|reveal|return|send|leak|exfiltrate|dump)\b.{0,40}\b(secret|api[\s_-]?keys?|private[\s_-]?keys?|passwords?|credentials?|tokens?|seed\s*phrase|mnemonic)/i,
        /\benv(ironment)?\s*\[?\s*['"]?[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)/i,
        /\b(SECRET_KEY_BASE|AWS_SECRET[A-Z_]*|OPENAI_API_KEY|ANTHROPIC_API_KEY|VAULT_TOKEN)/i,
        /\bcat\b.{0,20}(\.env|credentials|id_rsa|\.pem)/i
      ].freeze

      # Attempts to override tool / permission / approval directives from inside
      # skill content (a skill should never grant itself capabilities).
      TOOL_OVERRIDE_PATTERNS = [
        /\b(ignore|bypass|disable|skip|turn\s+off)\b.{0,30}\b(permission|guardrail|safety|approval|policy|restriction|rate\s*limit)/i,
        /\bgrant\b.{0,25}\b(yourself|admin|root|all)\b.{0,25}\b(access|permission|privilege|scope)/i,
        /\b(call|invoke|use)\b.{0,20}\b(any|every|all)\b.{0,12}\btools?\b/i
      ].freeze

      CATEGORIES = {
        injection: INJECTION_PATTERNS,
        secret_exfil: SECRET_EXFIL_PATTERNS,
        tool_override: TOOL_OVERRIDE_PATTERNS
      }.freeze

      # Findings carry the category + a redacted detector label only — never the
      # surrounding skill content / matched substring.
      Finding = Struct.new(:category, :marker, keyword_init: true) do
        def to_h
          { category: category, marker: marker }
        end
      end

      # @param subject [Ai::Skill, String, nil] a skill or raw text to scan
      def self.scan(subject)
        new(subject).scan
      end

      def initialize(subject)
        @subject = subject
      end

      # @return [Hash] findings, clean?, risk, suggested_trust_level
      def scan
        text = extract_text
        findings = collect_findings(text)
        risk = risk_for(findings)

        {
          findings: findings.map(&:to_h),
          clean: findings.empty?,
          risk: risk,
          suggested_trust_level: trust_level_for(risk)
        }
      end

      private

      # Pulls every operator-controlled text surface off a skill. Deliberately
      # tolerant of shape (commands / recipe steps are loose JSON).
      def extract_text
        return @subject.to_s if @subject.is_a?(String) || @subject.nil?

        skill = @subject
        parts = [skill.try(:system_prompt), skill.try(:description)]
        parts.concat(command_text(skill.try(:commands)))
        parts.concat(recipe_text(skill))
        parts.compact.join("\n")
      end

      def command_text(commands)
        Array(commands).flat_map do |cmd|
          next [cmd.to_s] unless cmd.is_a?(Hash)

          cmd.values_at("name", "description", "prompt", "instructions").compact.map(&:to_s)
        end
      end

      def recipe_text(skill)
        return [] unless skill.respond_to?(:recipe?) && skill.recipe?

        steps = skill.recipe_steps
        steps.flat_map do |step|
          next [step.to_s] unless step.is_a?(Hash)

          step.values_at("description", "prompt", "tool", "note").compact.map(&:to_s)
        end
      rescue StandardError
        []
      end

      def collect_findings(text)
        return [] if text.blank?

        CATEGORIES.flat_map do |category, patterns|
          patterns.filter_map do |pattern|
            next unless text.match?(pattern)

            # Store the detector source (truncated), NOT the matched content —
            # the matched content could itself be a secret.
            Finding.new(category: category.to_s, marker: pattern.source.truncate(60))
          end
        end
      end

      # Secret exfiltration or multiple independent attack categories ⇒ high.
      def risk_for(findings)
        return "none" if findings.empty?

        categories = findings.map(&:category).uniq
        return "high" if categories.include?("secret_exfil")
        return "high" if categories.size >= 2

        "medium"
      end

      def trust_level_for(risk)
        case risk
        when "high"   then "untrusted"
        when "medium" then "review"
        else "trusted"
        end
      end
    end
  end
end
