# frozen_string_literal: true

module Ai
  module CodeFactory
    class PreflightGateService
      class GateError < StandardError; end

      def initialize(account:, risk_contract: nil)
        @account = account
        @risk_contract = risk_contract
        @classifier = RiskClassifierService.new(account: account, risk_contract: risk_contract)
        @sha_validator = ShaValidationService.new(account: account)
        @logger = Rails.logger
      end

      # Evaluate preflight gate for a PR
      # Returns: { passed:, risk_tier:, required_checks:, review_state:, reason: }
      def evaluate(pr_number:, head_sha:, changed_files:, repository_id: nil)
        # Step 1: Classify risk
        classification = @classifier.classify_changes(changed_files: changed_files)

        # Step 2: Find or create review state
        contract = resolve_contract
        unless contract
          return { passed: false, risk_tier: nil, required_checks: [], review_state: nil,
                   reason: "No active risk contract found" }
        end

        review_state = find_or_create_review_state(
          contract: contract,
          pr_number: pr_number,
          head_sha: head_sha,
          repository_id: repository_id,
          classification: classification
        )

        # Step 3: Validate SHA freshness
        validation = @sha_validator.validate_review_state(
          review_state: review_state,
          current_head_sha: head_sha
        )

        if validation[:stale]
          review_state.mark_stale!(validation[:reason])
          return { passed: false, risk_tier: classification[:tier], required_checks: classification[:required_checks],
                   review_state: review_state, reason: validation[:reason] }
        end

        # Step 4: Gate passes - review can proceed
        review_state.mark_reviewing!

        {
          passed: true,
          risk_tier: classification[:tier],
          required_checks: classification[:required_checks],
          evidence_required: classification[:evidence_required],
          review_state: review_state,
          reason: nil
        }
      rescue StandardError => e
        @logger.error("[CodeFactory::PreflightGate] Error: #{e.message}")
        raise GateError, e.message
      end

      private

      def resolve_contract
        @risk_contract || @account.ai_code_factory_risk_contracts.active.order(created_at: :desc).first
      end

      def find_or_create_review_state(contract:, pr_number:, head_sha:, repository_id:, classification:)
        existing = @account.ai_code_factory_review_states
          .find_by(repository_id: repository_id, pr_number: pr_number, head_sha: head_sha)

        return existing if existing

        @account.ai_code_factory_review_states.create!(
          risk_contract: contract,
          repository_id: repository_id,
          pr_number: pr_number,
          head_sha: head_sha,
          risk_tier: classification[:tier],
          required_checks: classification[:required_checks]
        )
      end
    end
  end
end
