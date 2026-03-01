# frozen_string_literal: true

module Ai
  module CodeFactory
    class HarnessGap < ApplicationRecord
      self.table_name = "ai_code_factory_harness_gaps"

      INCIDENT_SOURCES = %w[production_regression test_failure review_finding manual].freeze
      STATUSES = %w[open in_progress case_added verified closed].freeze
      SEVERITIES = %w[low medium high critical].freeze

      belongs_to :account
      belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract",
                 foreign_key: "risk_contract_id", optional: true

      validates :incident_source, presence: true, inclusion: { in: INCIDENT_SOURCES }
      validates :incident_id, presence: true
      validates :description, presence: true
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :severity, presence: true, inclusion: { in: SEVERITIES }

      scope :open_gaps, -> { where(status: "open") }
      scope :in_progress, -> { where(status: "in_progress") }
      scope :past_sla, -> { where("sla_deadline < ? AND status NOT IN (?)", Time.current, %w[verified closed]) }
      scope :by_severity, ->(severity) { where(severity: severity) }
      scope :recent, -> { order(created_at: :desc) }

      before_validation :set_defaults, on: :create

      def add_test_case!(reference)
        update!(
          status: "case_added",
          test_case_added: true,
          test_case_reference: reference
        )
      end

      def verify!
        update!(status: "verified")
      end

      def close!(notes = nil)
        update!(
          status: "closed",
          resolution_notes: notes,
          resolved_at: Time.current,
          sla_met: sla_deadline.present? ? Time.current <= sla_deadline : nil
        )
      end

      def past_sla?
        sla_deadline.present? && Time.current > sla_deadline && !%w[verified closed].include?(status)
      end

      private

      def set_defaults
        self.status ||= "open"
        self.severity ||= "medium"
        self.metadata ||= {}
      end
    end
  end
end
