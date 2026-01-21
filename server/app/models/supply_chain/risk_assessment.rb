# frozen_string_literal: true

module SupplyChain
  class RiskAssessment < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_risk_assessments"

    # ============================================
    # Constants
    # ============================================
    ASSESSMENT_TYPES = %w[initial periodic incident renewal].freeze
    STATUSES = %w[draft in_progress pending_review completed expired].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :vendor, class_name: "SupplyChain::Vendor"
    belongs_to :account
    belongs_to :assessor, class_name: "User", optional: true

    has_many :questionnaire_responses, class_name: "SupplyChain::QuestionnaireResponse",
             foreign_key: :risk_assessment_id, dependent: :nullify

    # ============================================
    # Validations
    # ============================================
    validates :assessment_type, presence: true, inclusion: { in: ASSESSMENT_TYPES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :security_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :compliance_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :operational_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :overall_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :draft, -> { where(status: "draft") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :pending_review, -> { where(status: "pending_review") }
    scope :completed, -> { where(status: "completed") }
    scope :expired, -> { where(status: "expired") }
    scope :by_type, ->(type) { where(assessment_type: type) }
    scope :initial, -> { where(assessment_type: "initial") }
    scope :periodic, -> { where(assessment_type: "periodic") }
    scope :valid, -> { completed.where("valid_until IS NULL OR valid_until > ?", Time.current) }
    scope :expiring_soon, ->(days = 30) { where("valid_until <= ?", days.days.from_now) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields
    before_save :calculate_overall_score, if: :should_recalculate_score?
    after_save :update_vendor_assessment_date, if: :saved_change_to_status?

    # ============================================
    # Instance Methods
    # ============================================
    def draft?
      status == "draft"
    end

    def in_progress?
      status == "in_progress"
    end

    def pending_review?
      status == "pending_review"
    end

    def completed?
      status == "completed"
    end

    def expired?
      status == "expired"
    end

    def initial?
      assessment_type == "initial"
    end

    def periodic?
      assessment_type == "periodic"
    end

    def incident?
      assessment_type == "incident"
    end

    def renewal?
      assessment_type == "renewal"
    end

    def valid?
      completed? && (valid_until.nil? || valid_until > Time.current)
    end

    def expiring_soon?(days = 30)
      valid_until.present? && valid_until <= days.days.from_now
    end

    def days_until_expiry
      return nil unless valid_until.present?

      (valid_until.to_date - Date.current).to_i
    end

    def finding_count
      findings&.length || 0
    end

    def critical_findings
      findings&.select { |f| f["severity"] == "critical" } || []
    end

    def high_findings
      findings&.select { |f| f["severity"] == "high" } || []
    end

    def open_findings
      findings&.select { |f| f["status"] == "open" } || []
    end

    def recommendation_count
      recommendations&.length || 0
    end

    def risk_level
      case overall_score
      when 80..100 then "critical"
      when 60..79 then "high"
      when 30..59 then "medium"
      else "low"
      end
    end

    def start!
      update!(status: "in_progress", assessment_date: Time.current)
    end

    def submit_for_review!
      update!(status: "pending_review")
    end

    def complete!(valid_months = 12)
      update!(
        status: "completed",
        completed_at: Time.current,
        valid_until: valid_months.months.from_now
      )
    end

    def expire!
      update!(status: "expired")
    end

    def add_finding(title:, severity:, description:, category: nil, remediation: nil)
      finding = {
        id: SecureRandom.uuid,
        title: title,
        severity: severity,
        description: description,
        category: category,
        remediation: remediation,
        status: "open",
        created_at: Time.current.iso8601
      }

      self.findings = (findings || []) << finding
      save!
      finding
    end

    def resolve_finding(finding_id, resolution: nil)
      self.findings = findings.map do |f|
        if f["id"] == finding_id
          f.merge("status" => "resolved", "resolution" => resolution, "resolved_at" => Time.current.iso8601)
        else
          f
        end
      end
      save!
    end

    def add_recommendation(title:, priority:, description:, due_date: nil)
      rec = {
        id: SecureRandom.uuid,
        title: title,
        priority: priority,
        description: description,
        due_date: due_date&.iso8601,
        status: "pending",
        created_at: Time.current.iso8601
      }

      self.recommendations = (recommendations || []) << rec
      save!
      rec
    end

    def add_evidence(name:, type:, url: nil, notes: nil)
      ev = {
        id: SecureRandom.uuid,
        name: name,
        type: type,
        url: url,
        notes: notes,
        added_at: Time.current.iso8601
      }

      self.evidence = (evidence || []) << ev
      save!
      ev
    end

    def summary
      {
        id: id,
        vendor_id: vendor_id,
        vendor_name: vendor.name,
        assessment_type: assessment_type,
        status: status,
        scores: {
          security: security_score,
          compliance: compliance_score,
          operational: operational_score,
          overall: overall_score
        },
        risk_level: risk_level,
        finding_count: finding_count,
        critical_finding_count: critical_findings.length,
        open_finding_count: open_findings.length,
        recommendation_count: recommendation_count,
        assessment_date: assessment_date,
        completed_at: completed_at,
        valid_until: valid_until,
        is_valid: valid?,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.findings ||= []
      self.recommendations ||= []
      self.evidence ||= []
      self.metadata ||= {}
    end

    def should_recalculate_score?
      security_score_changed? || compliance_score_changed? || operational_score_changed?
    end

    def calculate_overall_score
      # Weighted average: Security 40%, Compliance 35%, Operational 25%
      self.overall_score = (
        (security_score * 0.4) +
        (compliance_score * 0.35) +
        (operational_score * 0.25)
      ).round(2)
    end

    def update_vendor_assessment_date
      return unless completed?

      vendor.update!(
        last_assessment_at: completed_at,
        risk_score: overall_score
      )
      vendor.schedule_next_assessment!
    end
  end
end
