# frozen_string_literal: true

module Ai
  class CompliancePolicy < ApplicationRecord
    self.table_name = "ai_compliance_policies"

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :violations, class_name: "Ai::PolicyViolation", foreign_key: :policy_id, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :policy_type, presence: true, inclusion: {
      in: %w[data_access model_usage output_filter rate_limit cost_limit approval_required retention audit custom]
    }
    validates :status, presence: true, inclusion: { in: %w[draft active disabled archived] }
    validates :enforcement_level, presence: true, inclusion: { in: %w[log warn block require_approval] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :system, -> { where(is_system: true) }
    scope :custom, -> { where(is_system: false) }
    scope :required, -> { where(is_required: true) }
    scope :by_type, ->(type) { where(policy_type: type) }
    scope :by_enforcement, ->(level) { where(enforcement_level: level) }
    scope :ordered_by_priority, -> { order(priority: :desc) }

    # Methods
    def active?
      status == "active"
    end

    def blocking?
      enforcement_level == "block"
    end

    def requires_approval?
      enforcement_level == "require_approval"
    end

    def activate!
      update!(status: "active", activated_at: Time.current)
    end

    def deactivate!
      update!(status: "disabled")
    end

    def record_violation!(source_type:, source_id:, description:, context: {}, severity: "medium")
      violations.create!(
        account: account,
        violation_id: SecureRandom.uuid,
        severity: severity,
        status: "open",
        source_type: source_type,
        source_id: source_id,
        description: description,
        context: context,
        detected_at: Time.current
      )
      increment!(:violation_count)
      update!(last_triggered_at: Time.current)
    end

    def applies_to?(resource)
      return true if applies_to.blank?

      resource_type = resource.class.name
      resource_tags = resource.try(:tags) || []

      # Check if policy applies to this resource type
      return false if applies_to["types"].present? && !applies_to["types"].include?(resource_type)

      # Check if policy applies to resources with specific tags
      return false if applies_to["tags"].present? && (applies_to["tags"] & resource_tags).empty?

      true
    end

    def evaluate(context)
      return { allowed: true, reason: nil } unless active?

      # Evaluate conditions against context
      conditions.each do |key, expected|
        actual = context[key.to_sym] || context[key.to_s]
        unless matches_condition?(actual, expected)
          return {
            allowed: !blocking?,
            reason: "Policy '#{name}' condition not met: #{key}",
            enforcement: enforcement_level
          }
        end
      end

      { allowed: true, reason: nil }
    end

    private

    def matches_condition?(actual, expected)
      case expected
      when Hash
        if expected["max"].present?
          return actual.to_f <= expected["max"].to_f
        elsif expected["min"].present?
          return actual.to_f >= expected["min"].to_f
        elsif expected["in"].present?
          return expected["in"].include?(actual)
        elsif expected["not_in"].present?
          return !expected["not_in"].include?(actual)
        end
      else
        return actual == expected
      end
      true
    end
  end
end
