# frozen_string_literal: true

module DataManagement
  # Configurable data retention policies for GDPR compliance
  class RetentionPolicy < ApplicationRecord
    # Table name handled by Data.table_name_prefix

    # Associations
    belongs_to :account, optional: true # null = system-wide default

    # Validations
    validates :data_type, presence: true
    validates :retention_days, presence: true, numericality: { greater_than: 0 }
    validates :action, presence: true, inclusion: { in: %w[delete anonymize archive] }
    validates :data_type, uniqueness: { scope: :account_id }

    # Scopes
    scope :active, -> { where(active: true) }
    scope :system_defaults, -> { where(account_id: nil) }
    scope :for_account, ->(account) { where(account_id: [ nil, account.id ]).order(account_id: :desc) }
    scope :by_data_type, ->(type) { where(data_type: type) }
    scope :due_for_enforcement, -> { active.where("last_enforced_at IS NULL OR last_enforced_at < ?", 1.day.ago) }

    # Default retention policies (system-wide)
    DEFAULT_POLICIES = {
      "audit_logs" => { retention_days: 365 * 7, action: "archive", legal_basis: "SOC 2, GDPR Art. 17(3)" },
      "user_activity" => { retention_days: 365, action: "anonymize", legal_basis: "GDPR Art. 5(1)(e)" },
      "payment_records" => { retention_days: 365 * 7, action: "archive", legal_basis: "Tax regulations" },
      "session_logs" => { retention_days: 90, action: "delete", legal_basis: "GDPR Art. 5(1)(e)" },
      "email_logs" => { retention_days: 365, action: "delete", legal_basis: "GDPR Art. 5(1)(e)" },
      "file_uploads" => { retention_days: 365 * 2, action: "delete", legal_basis: "Storage optimization" },
      "analytics_data" => { retention_days: 365 * 2, action: "anonymize", legal_basis: "GDPR Art. 5(1)(e)" },
      "webhook_logs" => { retention_days: 90, action: "delete", legal_basis: "GDPR Art. 5(1)(e)" },
      "api_request_logs" => { retention_days: 30, action: "delete", legal_basis: "GDPR Art. 5(1)(e)" }
    }.freeze

    # Class methods
    def self.policy_for(data_type, account = nil)
      if account
        for_account(account).find_by(data_type: data_type) || system_defaults.find_by(data_type: data_type)
      else
        system_defaults.find_by(data_type: data_type)
      end
    end

    def self.ensure_defaults!
      DEFAULT_POLICIES.each do |data_type, config|
        find_or_create_by!(account_id: nil, data_type: data_type) do |policy|
          policy.retention_days = config[:retention_days]
          policy.action = config[:action]
          policy.legal_basis = config[:legal_basis]
          policy.description = "Default retention policy for #{data_type.humanize.downcase}"
        end
      end
    end

    def self.data_types
      DEFAULT_POLICIES.keys
    end

    # Instance methods
    def cutoff_date
      retention_days.days.ago
    end

    def system_default?
      account_id.nil?
    end

    def record_enforcement(records_count)
      update!(
        last_enforced_at: Time.current,
        records_processed_count: records_processed_count + records_count
      )
    end

    def enforcement_due?
      return true if last_enforced_at.nil?

      last_enforced_at < 1.day.ago
    end

    def effective_for?(record_date)
      record_date < cutoff_date
    end
  end
end

# Backwards compatibility alias
