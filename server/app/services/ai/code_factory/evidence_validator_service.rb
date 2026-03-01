# frozen_string_literal: true

module Ai
  module CodeFactory
    class EvidenceValidatorService
      class ValidationError < StandardError; end

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Check if evidence is required for given changed files
      def evidence_required?(changed_files:, risk_contract: nil)
        contract = risk_contract || @account.ai_code_factory_risk_contracts.active.first
        return false unless contract

        classifier = RiskClassifierService.new(account: @account, risk_contract: contract)
        classification = classifier.classify_changes(changed_files: changed_files)
        classification[:evidence_required]
      end

      # Create an evidence manifest for a review state
      def create_manifest(review_state:, manifest_type:, artifacts: [], assertions: [])
        manifest = review_state.evidence_manifests.create!(
          account: @account,
          manifest_type: manifest_type,
          artifacts: artifacts,
          assertions: assertions,
          status: artifacts.any? ? "captured" : "pending",
          captured_at: artifacts.any? ? Time.current : nil
        )

        @logger.info("[CodeFactory::EvidenceValidator] Created manifest #{manifest.id} type=#{manifest_type}")
        manifest
      end

      # Validate evidence for a review state
      def validate_evidence(review_state:, manifest:)
        results = {
          assertions_passed: validate_assertions(manifest),
          artifacts_valid: validate_artifacts(manifest),
          timestamp_valid: validate_timestamps(manifest)
        }

        passed = results.values.all?

        manifest.verify!(passed: passed, details: results)

        @logger.info("[CodeFactory::EvidenceValidator] Evidence #{manifest.id} validation: #{passed ? 'PASSED' : 'FAILED'}")

        { passed: passed, results: results }
      rescue StandardError => e
        @logger.error("[CodeFactory::EvidenceValidator] Validation error: #{e.message}")
        manifest.verify!(passed: false, error: e.message)
        { passed: false, error: e.message }
      end

      private

      def validate_assertions(manifest)
        return true if manifest.assertions.blank?

        manifest.all_assertions_passed?
      end

      def validate_artifacts(manifest)
        return true if manifest.artifacts.blank?

        manifest.artifacts.all? do |artifact|
          artifact["sha256"].present? && artifact["url"].present?
        end
      end

      def validate_timestamps(manifest)
        return true unless manifest.captured_at

        # Evidence must be captured within last 24 hours
        manifest.captured_at > 24.hours.ago
      end
    end
  end
end
