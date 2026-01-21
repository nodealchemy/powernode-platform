# frozen_string_literal: true

module SupplyChain
  class Report < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_reports"

    # ============================================
    # Constants
    # ============================================
    REPORT_TYPES = %w[sbom_export vulnerability_report license_report attribution compliance_summary vendor_assessment custom].freeze
    FORMATS = %w[pdf json csv html xml spdx cyclonedx].freeze
    STATUSES = %w[pending generating completed failed expired].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :sbom, class_name: "SupplyChain::Sbom", optional: true
    belongs_to :created_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
    validates :format, presence: true, inclusion: { in: FORMATS }
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { where(status: "pending") }
    scope :generating, -> { where(status: "generating") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :expired, -> { where(status: "expired") }
    scope :by_type, ->(type) { where(report_type: type) }
    scope :by_format, ->(format) { where(format: format) }
    scope :sbom_exports, -> { where(report_type: "sbom_export") }
    scope :vulnerability_reports, -> { where(report_type: "vulnerability_report") }
    scope :license_reports, -> { where(report_type: "license_report") }
    scope :attribution_reports, -> { where(report_type: "attribution") }
    scope :compliance_reports, -> { where(report_type: "compliance_summary") }
    scope :available, -> { completed.where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expiring_soon, ->(days = 7) { where("expires_at <= ?", days.days.from_now) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def pending?
      status == "pending"
    end

    def generating?
      status == "generating"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def expired?
      status == "expired" || (expires_at.present? && expires_at < Time.current)
    end

    def available?
      completed? && !expired?
    end

    def downloadable?
      available? && file_path.present?
    end

    def sbom_export?
      report_type == "sbom_export"
    end

    def vulnerability_report?
      report_type == "vulnerability_report"
    end

    def license_report?
      report_type == "license_report"
    end

    def attribution?
      report_type == "attribution"
    end

    def compliance_summary?
      report_type == "compliance_summary"
    end

    def vendor_assessment?
      report_type == "vendor_assessment"
    end

    def formatted_size
      return nil unless file_size_bytes.present?

      if file_size_bytes >= 1_048_576
        "#{(file_size_bytes / 1_048_576.0).round(2)} MB"
      elsif file_size_bytes >= 1024
        "#{(file_size_bytes / 1024.0).round(2)} KB"
      else
        "#{file_size_bytes} bytes"
      end
    end

    def days_until_expiry
      return nil unless expires_at.present?

      (expires_at.to_date - Date.current).to_i
    end

    def start_generation!
      update!(status: "generating")
    end

    def complete_generation!(file_path:, file_url: nil, file_size: nil, summary_data: {})
      update!(
        status: "completed",
        file_path: file_path,
        file_url: file_url,
        file_size_bytes: file_size,
        summary: summary_data,
        generated_at: Time.current,
        expires_at: default_expiration
      )
    end

    def fail_generation!(error_message)
      update!(
        status: "failed",
        metadata: metadata.merge("error" => error_message)
      )
    end

    def expire!
      update!(status: "expired")
    end

    def extend_expiration!(days)
      new_expiry = (expires_at || Time.current) + days.days
      update!(expires_at: new_expiry)
    end

    def default_expiration
      case report_type
      when "sbom_export" then 30.days.from_now
      when "vulnerability_report" then 7.days.from_now
      when "license_report" then 30.days.from_now
      when "attribution" then 90.days.from_now
      when "compliance_summary" then 30.days.from_now
      when "vendor_assessment" then 90.days.from_now
      else 14.days.from_now
      end
    end

    def file_extension
      case format
      when "pdf" then ".pdf"
      when "json" then ".json"
      when "csv" then ".csv"
      when "html" then ".html"
      when "xml" then ".xml"
      when "spdx" then ".spdx.json"
      when "cyclonedx" then ".cdx.json"
      else ".txt"
      end
    end

    def suggested_filename
      timestamp = generated_at&.strftime("%Y%m%d") || Time.current.strftime("%Y%m%d")
      base_name = name.downcase.gsub(/[^a-z0-9]+/, "_")
      "#{base_name}_#{timestamp}#{file_extension}"
    end

    def summary_data
      {
        id: id,
        name: name,
        description: description,
        report_type: report_type,
        format: format,
        status: status,
        sbom_id: sbom_id,
        file_size_bytes: file_size_bytes,
        formatted_size: formatted_size,
        generated_at: generated_at,
        expires_at: expires_at,
        days_until_expiry: days_until_expiry,
        downloadable: downloadable?,
        created_at: created_at
      }
    end

    def detailed_report
      {
        summary: summary_data,
        parameters: parameters,
        report_summary: summary,
        file_url: file_url
      }
    end

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def generate_sbom_export(account:, sbom:, format: "cyclonedx", created_by: nil)
        create!(
          account: account,
          sbom: sbom,
          created_by: created_by,
          report_type: "sbom_export",
          format: format,
          name: "SBOM Export - #{sbom.name || sbom.sbom_id}",
          parameters: { sbom_id: sbom.id, format: format }
        )
      end

      def generate_vulnerability_report(account:, sbom: nil, created_by: nil, filters: {})
        name = sbom.present? ? "Vulnerability Report - #{sbom.name || sbom.sbom_id}" : "Vulnerability Report"

        create!(
          account: account,
          sbom: sbom,
          created_by: created_by,
          report_type: "vulnerability_report",
          format: "pdf",
          name: name,
          parameters: { sbom_id: sbom&.id, filters: filters }
        )
      end

      def generate_license_report(account:, sbom: nil, created_by: nil)
        name = sbom.present? ? "License Report - #{sbom.name || sbom.sbom_id}" : "License Report"

        create!(
          account: account,
          sbom: sbom,
          created_by: created_by,
          report_type: "license_report",
          format: "pdf",
          name: name,
          parameters: { sbom_id: sbom&.id }
        )
      end

      def generate_attribution(account:, sbom:, created_by: nil)
        create!(
          account: account,
          sbom: sbom,
          created_by: created_by,
          report_type: "attribution",
          format: "html",
          name: "Attribution Notice - #{sbom.name || sbom.sbom_id}",
          parameters: { sbom_id: sbom.id }
        )
      end

      def generate_compliance_summary(account:, compliance_type:, created_by: nil)
        create!(
          account: account,
          created_by: created_by,
          report_type: "compliance_summary",
          format: "pdf",
          name: "Compliance Summary - #{compliance_type.upcase}",
          parameters: { compliance_type: compliance_type }
        )
      end
    end

    private

    def sanitize_jsonb_fields
      self.parameters ||= {}
      self.summary ||= {}
      self.metadata ||= {}
    end
  end
end
