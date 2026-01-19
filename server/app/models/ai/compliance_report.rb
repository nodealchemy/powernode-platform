# frozen_string_literal: true

module Ai
  class ComplianceReport < ApplicationRecord
    self.table_name = "ai_compliance_reports"

    # Associations
    belongs_to :account
    belongs_to :generated_by, class_name: "User", optional: true

    # Validations
    validates :report_id, presence: true, uniqueness: true
    validates :report_type, presence: true, inclusion: {
      in: %w[soc2 hipaa gdpr pci_dss iso27001 custom audit_summary violation_summary data_inventory]
    }
    validates :status, presence: true, inclusion: { in: %w[generating completed failed expired] }
    validates :format, presence: true, inclusion: { in: %w[pdf html json csv] }

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :generating, -> { where(status: "generating") }
    scope :by_type, ->(type) { where(report_type: type) }
    scope :recent, -> { order(generated_at: :desc) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    # Callbacks
    before_validation :set_report_id, on: :create

    # Methods
    def completed?
      status == "completed"
    end

    def generating?
      status == "generating"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def available?
      completed? && !expired? && file_path.present?
    end

    def complete!(file_path:, file_size:, summary_data: {})
      update!(
        status: "completed",
        file_path: file_path,
        file_size_bytes: file_size,
        summary_data: summary_data,
        generated_at: Time.current,
        expires_at: 30.days.from_now
      )
    end

    def fail!(error_message = nil)
      update!(
        status: "failed",
        summary_data: summary_data.merge(error: error_message)
      )
    end

    def period_description
      return "All time" if period_start.blank? && period_end.blank?
      return "Since #{period_start.to_date}" if period_end.blank?
      return "Until #{period_end.to_date}" if period_start.blank?

      "#{period_start.to_date} to #{period_end.to_date}"
    end

    private

    def set_report_id
      self.report_id ||= SecureRandom.uuid
    end
  end
end
