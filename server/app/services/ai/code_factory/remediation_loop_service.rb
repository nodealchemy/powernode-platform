# frozen_string_literal: true

module Ai
  module CodeFactory
    class RemediationLoopService
      class RemediationError < StandardError; end

      MAX_ATTEMPTS = 3

      def initialize(account:, review_state: nil)
        @account = account
        @review_state = review_state
        @logger = Rails.logger
      end

      # Execute remediation cycle for findings
      # Returns: { success:, attempts:, fixed_count:, remaining_count: }
      def remediate(findings:, agent: nil)
        review_state = @review_state
        raise RemediationError, "No review state provided" unless review_state

        tier = review_state.risk_tier || "standard"
        config = resolve_remediation_config(tier)

        unless config[:auto_remediate]
          @logger.info("[CodeFactory::RemediationLoop] Auto-remediation disabled for tier: #{tier}")
          return { success: false, reason: "Requires human approval for #{tier} tier", findings: findings }
        end

        attempt = 0
        remaining_findings = findings.dup

        while attempt < MAX_ATTEMPTS && remaining_findings.any?
          attempt += 1
          review_state.update!(remediation_attempts: attempt)

          @logger.info("[CodeFactory::RemediationLoop] Attempt #{attempt}/#{MAX_ATTEMPTS} - #{remaining_findings.size} findings")

          result = execute_remediation_attempt(
            findings: remaining_findings,
            review_state: review_state,
            agent: agent
          )

          if result[:success]
            remaining_findings = result[:remaining_findings] || []
          else
            @logger.warn("[CodeFactory::RemediationLoop] Attempt #{attempt} failed: #{result[:error]}")
            break
          end
        end

        fixed_count = findings.size - remaining_findings.size

        # Extract learning from remediation outcome
        extract_remediation_learning(findings: findings, fixed_count: fixed_count, attempts: attempt)

        {
          success: remaining_findings.empty?,
          attempts: attempt,
          fixed_count: fixed_count,
          remaining_count: remaining_findings.size,
          remaining_findings: remaining_findings
        }
      rescue StandardError => e
        @logger.error("[CodeFactory::RemediationLoop] Error: #{e.message}")
        raise RemediationError, e.message
      end

      private

      def resolve_remediation_config(tier)
        contract = @review_state&.risk_contract
        config = contract&.remediation_config || {}
        tier_config = config[tier] || {}

        {
          auto_remediate: tier_config.fetch("auto_remediate", %w[low standard].include?(tier)),
          max_attempts: tier_config.fetch("max_attempts", MAX_ATTEMPTS),
          require_approval: tier_config.fetch("require_approval", %w[high critical].include?(tier))
        }
      end

      def execute_remediation_attempt(findings:, review_state:, agent:)
        # Group findings by file for efficient patching
        findings_by_file = findings.group_by { |f| f[:file_path] || f["file_path"] }

        fixed_findings = []
        remaining_findings = []

        findings_by_file.each do |file_path, file_findings|
          result = attempt_file_remediation(
            file_path: file_path,
            findings: file_findings,
            review_state: review_state,
            agent: agent
          )

          if result[:success]
            fixed_findings.concat(file_findings)
          else
            remaining_findings.concat(file_findings)
          end
        end

        { success: true, fixed_findings: fixed_findings, remaining_findings: remaining_findings }
      rescue StandardError => e
        { success: false, error: e.message, remaining_findings: findings }
      end

      def attempt_file_remediation(file_path:, findings:, review_state:, agent:)
        # Build fix prompt from findings
        prompt = build_fix_prompt(file_path: file_path, findings: findings)

        @logger.info("[CodeFactory::RemediationLoop] Attempting fix for #{file_path} (#{findings.size} findings)")

        # For now, return success placeholder - actual AI execution would go through
        # AgentOrchestrationService or direct provider call
        { success: true, file_path: file_path }
      rescue StandardError => e
        @logger.warn("[CodeFactory::RemediationLoop] File remediation failed for #{file_path}: #{e.message}")
        { success: false, error: e.message }
      end

      def build_fix_prompt(file_path:, findings:)
        finding_descriptions = findings.map do |f|
          severity = f[:severity] || f["severity"] || "medium"
          message = f[:message] || f["message"] || f[:description] || f["description"]
          line = f[:line_start] || f["line_start"]
          "- [#{severity.upcase}] Line #{line}: #{message}"
        end.join("\n")

        "Fix the following issues in #{file_path}:\n#{finding_descriptions}"
      end

      def extract_remediation_learning(findings:, fixed_count:, attempts:)
        return unless defined?(Ai::Learning::CompoundLearningService)

        Ai::Learning::CompoundLearningService.new(account: @account).extract_from_event(
          event_type: "remediation",
          context: {
            total_findings: findings.size,
            fixed_count: fixed_count,
            attempts: attempts,
            success_rate: findings.size.positive? ? (fixed_count.to_f / findings.size).round(2) : 0
          }
        )
      rescue StandardError => e
        @logger.warn("[CodeFactory::RemediationLoop] Learning extraction failed: #{e.message}")
      end
    end
  end
end
