# frozen_string_literal: true

module SupplyChain
  class Vendor < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_vendors"

    # ============================================
    # Constants
    # ============================================
    VENDOR_TYPES = %w[saas api library infrastructure hardware consulting other].freeze
    RISK_TIERS = %w[critical high medium low].freeze
    STATUSES = %w[active inactive under_review terminated].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :risk_assessments, class_name: "SupplyChain::RiskAssessment",
             foreign_key: :vendor_id, dependent: :destroy
    has_many :questionnaire_responses, class_name: "SupplyChain::QuestionnaireResponse",
             foreign_key: :vendor_id, dependent: :destroy
    has_many :monitoring_events, class_name: "SupplyChain::VendorMonitoringEvent",
             foreign_key: :vendor_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :account_id },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "only lowercase letters, numbers, hyphens, and underscores" }
    validates :vendor_type, presence: true, inclusion: { in: VENDOR_TYPES }
    validates :risk_tier, presence: true, inclusion: { in: RISK_TIERS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :under_review, -> { where(status: "under_review") }
    scope :by_type, ->(type) { where(vendor_type: type) }
    scope :by_risk_tier, ->(tier) { where(risk_tier: tier) }
    scope :critical_risk, -> { where(risk_tier: "critical") }
    scope :high_risk, -> { where(risk_tier: %w[critical high]) }
    scope :handles_sensitive_data, -> { where(handles_pii: true).or(where(handles_phi: true)).or(where(handles_pci: true)) }
    scope :needs_assessment, -> { where("next_assessment_due IS NULL OR next_assessment_due <= ?", Time.current) }
    scope :alphabetical, -> { order(name: :asc) }
    scope :ordered_by_risk, -> { order(Arel.sql("CASE risk_tier WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 END")) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      status == "active"
    end

    def inactive?
      status == "inactive"
    end

    def under_review?
      status == "under_review"
    end

    def terminated?
      status == "terminated"
    end

    def critical_risk?
      risk_tier == "critical"
    end

    def high_risk?
      risk_tier.in?(%w[critical high])
    end

    def handles_sensitive_data?
      handles_pii || handles_phi || handles_pci
    end

    def needs_assessment?
      next_assessment_due.nil? || next_assessment_due <= Time.current
    end

    def has_valid_baa?
      has_baa && handles_phi
    end

    def has_valid_dpa?
      has_dpa && handles_pii
    end

    def contract_active?
      return false if contract_end_date.nil?

      contract_end_date > Time.current
    end

    def days_until_contract_expiry
      return nil unless contract_end_date.present?

      (contract_end_date.to_date - Date.current).to_i
    end

    def activate!
      update!(status: "active")
    end

    def deactivate!
      update!(status: "inactive")
    end

    def start_review!
      update!(status: "under_review")
    end

    def terminate!
      update!(status: "terminated")
    end

    def latest_assessment
      risk_assessments.order(created_at: :desc).first
    end

    def latest_questionnaire
      questionnaire_responses.order(created_at: :desc).first
    end

    def unacknowledged_events
      monitoring_events.where(is_acknowledged: false)
    end

    def critical_events
      monitoring_events.where(severity: "critical")
    end

    def update_risk_score!(score)
      tier = case score
             when 80..100 then "critical"
             when 60..79 then "high"
             when 30..59 then "medium"
             else "low"
             end

      update!(risk_score: score, risk_tier: tier)
    end

    def calculate_risk_score!
      assessment = latest_assessment
      return update!(risk_score: 50) unless assessment

      # Invert scores since assessments are "good" scores (high=good) but risk should be "bad" (high=bad)
      avg = (assessment.security_score + assessment.compliance_score + assessment.operational_score) / 3.0
      score = (100 - avg).round
      update_risk_score!(score)
    end

    def data_sensitivity
      return "high" if handles_phi
      return "medium" if handles_pci || handles_pii

      "low"
    end

    def schedule_next_assessment!(months = nil)
      months ||= case risk_tier
                 when "critical" then 3
                 when "high" then 6
                 when "medium" then 12
                 else 24
                 end

      update!(next_assessment_due: months.months.from_now)
    end

    def add_certification(name:, expires_at: nil, verified: false)
      cert = {
        name: name,
        expires_at: expires_at&.iso8601,
        verified: verified,
        added_at: Time.current.iso8601
      }

      self.certifications = (certifications + [cert])
      save!
    end

    def remove_certification(name)
      self.certifications = certifications.reject { |c| c["name"] == name }
      save!
    end

    def has_certification?(name)
      certifications.any? { |c| c["name"] == name }
    end

    def soc2_certified?
      has_certification?("SOC 2 Type II") || has_certification?("SOC 2 Type I")
    end

    def iso27001_certified?
      has_certification?("ISO 27001")
    end

    def summary
      {
        id: id,
        name: name,
        slug: slug,
        vendor_type: vendor_type,
        status: status,
        risk_tier: risk_tier,
        risk_score: risk_score,
        handles_sensitive_data: handles_sensitive_data?,
        handles_pii: handles_pii,
        handles_phi: handles_phi,
        handles_pci: handles_pci,
        has_baa: has_baa,
        has_dpa: has_dpa,
        certifications: certifications,
        last_assessment_at: last_assessment_at,
        next_assessment_due: next_assessment_due,
        needs_assessment: needs_assessment?,
        contract_end_date: contract_end_date,
        website: website,
        created_at: created_at
      }
    end

    private

    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      self.slug = base_slug

      counter = 1
      while account.supply_chain_vendors.where(slug: slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def sanitize_jsonb_fields
      self.certifications ||= []
      self.security_contacts ||= []
      self.metadata ||= {}
    end
  end
end
