# frozen_string_literal: true

module Ai
  module CodeFactory
    class RiskClassifierService
      class ClassificationError < StandardError; end

      TIER_PRIORITY = { "critical" => 4, "high" => 3, "standard" => 2, "low" => 1 }.freeze

      def initialize(account:, risk_contract: nil)
        @account = account
        @risk_contract = risk_contract
        @logger = Rails.logger
      end

      # Classify changed files against risk contract tiers
      # Returns: { tier:, matched_rules:, required_checks:, evidence_required: }
      def classify_changes(changed_files:)
        contract = resolve_contract
        return default_classification if contract.nil?

        highest_tier = contract.highest_tier_for_files(changed_files)
        return default_classification if highest_tier.nil?

        {
          tier: highest_tier["tier"],
          matched_rules: matched_rules_for_files(contract, changed_files),
          required_checks: highest_tier["required_checks"] || [],
          evidence_required: highest_tier["evidence_required"] || false,
          min_reviewers: highest_tier["min_reviewers"] || 0
        }
      end

      # Classify from raw diff text
      def classify_diff(diff_text:)
        changed_files = extract_files_from_diff(diff_text)
        classify_changes(changed_files: changed_files)
      end

      private

      def resolve_contract
        @risk_contract || @account.ai_code_factory_risk_contracts.active.order(created_at: :desc).first
      end

      def default_classification
        { tier: "low", matched_rules: [], required_checks: [], evidence_required: false, min_reviewers: 0 }
      end

      def matched_rules_for_files(contract, files)
        rules = []
        files.each do |file|
          tier = contract.tier_for_file(file)
          next unless tier

          rules << { file: file, tier: tier["tier"], patterns: tier["patterns"] }
        end
        rules
      end

      def extract_files_from_diff(diff_text)
        diff_text.scan(%r{^(?:diff --git a/(.+?) b/|^\+\+\+ b/(.+?)$)}).flatten.compact.uniq
      end
    end
  end
end
