# frozen_string_literal: true

module SupplyChain
  class VendorMonitoringEvent < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_vendor_monitoring_events"

    # ============================================
    # Constants
    # ============================================
    EVENT_TYPES = %w[security_incident breach certification_expiry contract_renewal service_degradation compliance_update news_alert].freeze
    SEVERITIES = %w[critical high medium low info].freeze
    SOURCES = %w[internal external automated manual].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :vendor, class_name: "SupplyChain::Vendor"
    belongs_to :account
    belongs_to :acknowledged_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
    validates :severity, presence: true, inclusion: { in: SEVERITIES }
    validates :source, presence: true, inclusion: { in: SOURCES }
    validates :title, presence: true
    validates :detected_at, presence: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_type, ->(type) { where(event_type: type) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :by_source, ->(source) { where(source: source) }
    scope :security_incidents, -> { where(event_type: "security_incident") }
    scope :breaches, -> { where(event_type: "breach") }
    scope :certification_expiries, -> { where(event_type: "certification_expiry") }
    scope :critical, -> { where(severity: "critical") }
    scope :high_severity, -> { where(severity: %w[critical high]) }
    scope :acknowledged, -> { where(is_acknowledged: true) }
    scope :unacknowledged, -> { where(is_acknowledged: false) }
    scope :resolved, -> { where.not(resolved_at: nil) }
    scope :unresolved, -> { where(resolved_at: nil) }
    scope :active, -> { unacknowledged.unresolved }
    scope :for_vendor, ->(vendor_id) { where(vendor_id: vendor_id) }
    scope :recent, -> { order(detected_at: :desc) }
    scope :detected_after, ->(time) { where("detected_at >= ?", time) }
    scope :detected_before, ->(time) { where("detected_at <= ?", time) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :set_detected_at, on: :create
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def security_incident?
      event_type == "security_incident"
    end

    def breach?
      event_type == "breach"
    end

    def certification_expiry?
      event_type == "certification_expiry"
    end

    def contract_renewal?
      event_type == "contract_renewal"
    end

    def service_degradation?
      event_type == "service_degradation"
    end

    def compliance_update?
      event_type == "compliance_update"
    end

    def news_alert?
      event_type == "news_alert"
    end

    def critical?
      severity == "critical"
    end

    def high?
      severity == "high"
    end

    def high_severity?
      severity.in?(%w[critical high])
    end

    def acknowledged?
      is_acknowledged
    end

    def unacknowledged?
      !is_acknowledged
    end

    def resolved?
      resolved_at.present?
    end

    def unresolved?
      resolved_at.nil?
    end

    def active?
      unacknowledged? && unresolved?
    end

    def acknowledge!(user)
      update!(
        is_acknowledged: true,
        acknowledged_at: Time.current,
        acknowledged_by: user
      )
    end

    def resolve!
      update!(resolved_at: Time.current)
    end

    def reopen!
      update!(
        is_acknowledged: false,
        acknowledged_at: nil,
        acknowledged_by: nil,
        resolved_at: nil
      )
    end

    def add_recommended_action(action:, priority: "medium", due_date: nil)
      rec = {
        id: SecureRandom.uuid,
        action: action,
        priority: priority,
        due_date: due_date&.iso8601,
        status: "pending",
        added_at: Time.current.iso8601
      }

      self.recommended_actions = (recommended_actions || []) << rec
      save!
      rec
    end

    def complete_action(action_id)
      self.recommended_actions = recommended_actions.map do |a|
        if a["id"] == action_id
          a.merge("status" => "completed", "completed_at" => Time.current.iso8601)
        else
          a
        end
      end
      save!
    end

    def pending_actions
      recommended_actions&.select { |a| a["status"] == "pending" } || []
    end

    def completed_actions
      recommended_actions&.select { |a| a["status"] == "completed" } || []
    end

    def days_since_detection
      return 0 unless detected_at.present?

      (Date.current - detected_at.to_date).to_i
    end

    def time_to_acknowledge
      return nil unless acknowledged_at.present? && detected_at.present?

      ((acknowledged_at - detected_at) / 1.hour).round(2)
    end

    def time_to_resolve
      return nil unless resolved_at.present? && detected_at.present?

      ((resolved_at - detected_at) / 1.hour).round(2)
    end

    def summary
      {
        id: id,
        vendor_id: vendor_id,
        vendor_name: vendor.name,
        event_type: event_type,
        severity: severity,
        source: source,
        title: title,
        description: description,
        external_url: external_url,
        is_acknowledged: is_acknowledged,
        is_resolved: resolved?,
        pending_action_count: pending_actions.length,
        detected_at: detected_at,
        acknowledged_at: acknowledged_at,
        resolved_at: resolved_at,
        days_since_detection: days_since_detection,
        created_at: created_at
      }
    end

    def detailed_event
      {
        summary: summary,
        recommended_actions: recommended_actions,
        affected_services: affected_services,
        acknowledged_by: acknowledged_by&.email,
        time_to_acknowledge_hours: time_to_acknowledge,
        time_to_resolve_hours: time_to_resolve
      }
    end

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def create_security_incident(vendor:, account:, title:, severity: "high", **options)
        create!(
          vendor: vendor,
          account: account,
          event_type: "security_incident",
          severity: severity,
          source: options[:source] || "external",
          title: title,
          description: options[:description],
          external_url: options[:external_url],
          recommended_actions: options[:recommended_actions] || []
        )
      end

      def create_certification_expiry(vendor:, account:, certification_name:, expires_at:)
        days_until = (expires_at.to_date - Date.current).to_i
        severity = days_until <= 7 ? "critical" : (days_until <= 30 ? "high" : "medium")

        create!(
          vendor: vendor,
          account: account,
          event_type: "certification_expiry",
          severity: severity,
          source: "automated",
          title: "#{certification_name} certification expiring",
          description: "The #{certification_name} certification for #{vendor.name} expires on #{expires_at.to_date}",
          recommended_actions: [
            {
              id: SecureRandom.uuid,
              action: "Request updated certification from vendor",
              priority: "high",
              due_date: (expires_at - 14.days).iso8601,
              status: "pending",
              added_at: Time.current.iso8601
            }
          ]
        )
      end

      def create_contract_renewal(vendor:, account:, renewal_date:)
        days_until = (renewal_date.to_date - Date.current).to_i
        severity = days_until <= 14 ? "high" : "medium"

        create!(
          vendor: vendor,
          account: account,
          event_type: "contract_renewal",
          severity: severity,
          source: "automated",
          title: "Contract renewal due",
          description: "Contract with #{vendor.name} is due for renewal on #{renewal_date.to_date}",
          recommended_actions: [
            {
              id: SecureRandom.uuid,
              action: "Review contract terms and initiate renewal process",
              priority: severity,
              due_date: (renewal_date - 30.days).iso8601,
              status: "pending",
              added_at: Time.current.iso8601
            },
            {
              id: SecureRandom.uuid,
              action: "Conduct vendor risk reassessment before renewal",
              priority: "medium",
              due_date: (renewal_date - 45.days).iso8601,
              status: "pending",
              added_at: Time.current.iso8601
            }
          ]
        )
      end
    end

    private

    def set_detected_at
      self.detected_at ||= Time.current
    end

    def sanitize_jsonb_fields
      self.recommended_actions ||= []
      self.affected_services ||= []
      self.metadata ||= {}
    end
  end
end
