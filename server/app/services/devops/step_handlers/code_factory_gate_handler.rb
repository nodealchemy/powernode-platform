# frozen_string_literal: true

module Devops
  module StepHandlers
    class CodeFactoryGateHandler < BaseHandler
      def execute
        changed_files = resolve_input("changed_files") || []
        pr_number = resolve_input("pr_number")&.to_i
        head_sha = resolve_input("head_sha")
        contract_id = resolve_input("contract_id")

        unless pr_number && head_sha
          return failure_result("Missing required inputs: pr_number and head_sha")
        end

        contract = contract_id.present? ?
          account.ai_code_factory_risk_contracts.find_by(id: contract_id) : nil

        service = ::Ai::CodeFactory::PreflightGateService.new(
          account: account,
          risk_contract: contract
        )

        result = service.evaluate(
          pr_number: pr_number,
          head_sha: head_sha,
          changed_files: changed_files,
          repository_id: step.pipeline&.repository_id
        )

        if result[:passed]
          success_result(
            risk_tier: result[:risk_tier],
            required_checks: result[:required_checks],
            evidence_required: result[:evidence_required],
            review_state_id: result[:review_state]&.id
          )
        else
          failure_result("Preflight gate failed: #{result[:reason]}")
        end
      rescue StandardError => e
        failure_result("Code Factory gate error: #{e.message}")
      end

      private

      def account
        @account ||= step.pipeline&.account
      end
    end
  end
end
