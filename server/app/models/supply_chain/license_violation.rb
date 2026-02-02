# frozen_string_literal: true

module SupplyChain
  class LicenseViolation < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_license_violations"

    # ============================================
    # Constants
    # ============================================
    VIOLATION_TYPES = %w[denied copyleft incompatible unknown expired].freeze
    SEVERITIES = %w[critical high medium low].freeze
    STATUSES = %w[open reviewing resolved exception_granted wont_fix].freeze
    EXCEPTION_STATUSES = %w[pending approved rejected expired].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :sbom, class_name: "SupplyChain::Sbom"
    belongs_to :sbom_component, class_name: "SupplyChain::SbomComponent"
    belongs_to :license_policy, class_name: "SupplyChain::LicensePolicy"
    belongs_to :license, class_name: "SupplyChain::License", optional: true
    belongs_to :exception_approved_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :violation_type, presence: true, inclusion: { in: VIOLATION_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :exception_status, inclusion: { in: EXCEPTION_STATUSES }, allow_nil: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_type, ->(type) { where(violation_type: type) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :by_status, ->(status) { where(status: status) }
    scope :open, -> { where(status: "open") }
    scope :reviewing, -> { where(status: "reviewing") }
    scope :resolved, -> { where(status: "resolved") }
    scope :exception_granted, -> { where(status: "exception_granted") }
    scope :actionable, -> { where(status: %w[open reviewing]) }
    scope :critical, -> { where(severity: "critical") }
    scope :high, -> { where(severity: "high") }
    scope :with_exception_requested, -> { where(exception_requested: true) }
    scope :pending_exception, -> { where(exception_requested: true, exception_status: "pending") }
    scope :recent, -> { order(created_at: :desc) }
    scope :ordered_by_severity, -> { order(Arel.sql("CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 END")) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_validation :set_severity_from_type

    # ============================================
    # Instance Methods
    # ============================================
    def open?
      status == "open"
    end

    def reviewing?
      status == "reviewing"
    end

    def resolved?
      status == "resolved"
    end

    def exception_granted?
      status == "exception_granted"
    end

    def wont_fix?
      status == "wont_fix"
    end

    def actionable?
      %w[open reviewing].include?(status)
    end

    def denied?
      violation_type == "denied"
    end

    def copyleft?
      violation_type == "copyleft"
    end

    def incompatible?
      violation_type == "incompatible"
    end

    def unknown?
      violation_type == "unknown"
    end

    def has_ai_remediation?
      ai_remediation.present? && ai_remediation.any?
    end

    def exception_pending?
      exception_requested && exception_status == "pending"
    end

    def exception_approved?
      exception_status == "approved"
    end

    def exception_expired?
      exception_expires_at.present? && exception_expires_at < Time.current
    end

    def start_review!
      update!(status: "reviewing")
    end

    def resolve!(resolution: nil, notes: nil, resolved_by: nil)
      self.metadata ||= {}
      update!(
        status: "resolved",
        metadata: metadata.merge(
          "resolution_reason" => resolution,
          "resolved_at" => Time.current.iso8601,
          "resolved_by_id" => resolved_by&.id,
          "notes" => notes
        )
      )
    end

    def wont_fix!(reason = nil)
      self.metadata ||= {}
      update!(
        status: "wont_fix",
        metadata: metadata.merge("wont_fix_reason" => reason)
      )
    end

    def request_exception!(justification: nil, expires_at: nil, requested_by: nil)
      update!(
        exception_requested: true,
        exception_status: "pending",
        exception_reason: justification,
        exception_expires_at: expires_at
      )
    end

    def approve_exception!(approved_by: nil, notes: nil, expires_at: nil)
      self.metadata ||= {}
      update!(
        status: "exception_granted",
        exception_status: "approved",
        exception_approved_by: approved_by,
        exception_approved_at: Time.current,
        exception_expires_at: expires_at,
        metadata: metadata.merge("approval_notes" => notes)
      )
    end

    def reject_exception!(rejected_by: nil, reason: nil)
      self.metadata ||= {}
      update!(
        exception_status: "rejected",
        exception_approved_by: rejected_by,
        exception_approved_at: Time.current,
        metadata: metadata.merge("rejection_reason" => reason)
      )
    end

    def component_name
      sbom_component.full_name
    end

    def component_version
      sbom_component.version
    end

    def license_name
      license&.name || sbom_component.license_name || "Unknown"
    end

    def license_spdx_id
      license&.spdx_id || sbom_component.license_spdx_id
    end

    def policy_name
      license_policy.name
    end

    # Helper methods for fields stored in metadata
    def resolved_at
      metadata&.dig("resolved_at")&.then { |t| Time.parse(t) rescue nil }
    end

    def resolved_by_id
      metadata&.dig("resolved_by_id")
    end

    def notes
      metadata&.dig("notes")
    end

    def notes=(value)
      self.metadata ||= {}
      self.metadata["notes"] = value
    end

    def exception_justification
      exception_reason
    end

    def recommendation
      metadata&.dig("recommendation")
    end

    def summary
      {
        id: id,
        violation_type: violation_type,
        severity: severity,
        status: status,
        component: {
          id: sbom_component_id,
          name: component_name,
          version: component_version
        },
        license: {
          spdx_id: license_spdx_id,
          name: license_name
        },
        policy: {
          id: license_policy_id,
          name: policy_name
        },
        exception_requested: exception_requested,
        exception_status: exception_status,
        has_ai_remediation: has_ai_remediation?,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.ai_remediation ||= {}
      self.metadata ||= {}
    end

    def set_severity_from_type
      # Only set severity automatically if:
      # 1. It's a new record without a severity set, OR
      # 2. The violation_type has changed on an existing record
      # Don't override explicitly set severity for new records
      return if severity.present? && (new_record? || !violation_type_changed?)

      self.severity = case violation_type
      when "denied" then "high"
      when "copyleft" then "high"
      when "incompatible" then "medium"
      when "unknown" then "medium"
      when "expired" then "low"
      else "medium"
      end
    end
  end
end
