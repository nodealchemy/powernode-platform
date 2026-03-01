# frozen_string_literal: true

module Ai
  module CodeFactory
    class EvidenceManifest < ApplicationRecord
      self.table_name = "ai_code_factory_evidence_manifests"

      MANIFEST_TYPES = %w[browser_test screenshot video assertion combined].freeze
      STATUSES = %w[pending captured verified failed].freeze

      belongs_to :account
      belongs_to :review_state, class_name: "Ai::CodeFactory::ReviewState", foreign_key: "review_state_id"

      validates :manifest_type, presence: true, inclusion: { in: MANIFEST_TYPES }
      validates :status, presence: true, inclusion: { in: STATUSES }

      scope :pending, -> { where(status: "pending") }
      scope :verified, -> { where(status: "verified") }
      scope :failed, -> { where(status: "failed") }
      scope :recent, -> { order(created_at: :desc) }

      before_validation :set_defaults, on: :create

      def capture!(new_artifacts, new_assertions = [])
        update!(
          status: "captured",
          artifacts: new_artifacts,
          assertions: new_assertions,
          captured_at: Time.current
        )
      end

      def verify!(result)
        new_status = result[:passed] ? "verified" : "failed"
        update!(
          status: new_status,
          verification_result: result,
          verified_at: Time.current
        )

        if new_status == "verified"
          review_state.update!(evidence_verified: true)
        end
      end

      def all_assertions_passed?
        return true if assertions.blank?

        assertions.all? { |a| a["passed"] == true }
      end

      private

      def set_defaults
        self.status ||= "pending"
        self.assertions ||= []
        self.artifacts ||= []
        self.verification_result ||= {}
        self.metadata ||= {}
      end
    end
  end
end
