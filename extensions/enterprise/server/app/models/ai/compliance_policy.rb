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

      # Delegate to type-specific evaluator when available
      case policy_type
      when "rate_limit"
        evaluate_rate_limit(context)
      when "cost_limit"
        evaluate_cost_limit(context)
      when "output_filter"
        evaluate_output_filter(context)
      else
        evaluate_generic(context)
      end
    end

    private

    # Rate limit: count recent executions against configured thresholds
    def evaluate_rate_limit(context)
      limits = conditions["limits"] || {}
      agent_id = context[:agent_id] || context["agent_id"]
      user_id = context[:user_id] || context["user_id"]

      limits.each do |scope_key, threshold|
        count = count_executions_for(scope_key, agent_id: agent_id, user_id: user_id)
        next if count.nil? # skip scopes we cannot evaluate (missing user/account)

        if count >= threshold.to_i
          return {
            allowed: !blocking?,
            reason: "Policy '#{name}' rate limit exceeded: #{scope_key} (#{count}/#{threshold})",
            enforcement: enforcement_level
          }
        end
      end

      { allowed: true, reason: nil }
    end

    # Cost limit: check estimated or actual cost against threshold
    def evaluate_cost_limit(context)
      threshold = conditions["cost_threshold_usd"]&.to_f
      return { allowed: true, reason: nil } unless threshold

      actual_cost = (context[:cost_usd] || context["cost_usd"])&.to_f
      return { allowed: true, reason: nil } unless actual_cost # no cost data yet — allow

      if actual_cost > threshold
        return {
          allowed: !blocking?,
          reason: "Policy '#{name}' cost cap exceeded: $#{actual_cost} > $#{threshold}",
          enforcement: enforcement_level
        }
      end

      { allowed: true, reason: nil }
    end

    # Output filter: check text content against configured patterns (used in post-execution)
    def evaluate_output_filter(context)
      text = context[:output_text] || context["output_text"] || ""
      return { allowed: true, reason: nil } if text.blank?

      regex_rules = conditions["regex_rules"] || []
      regex_rules.each do |rule|
        pattern = rule["pattern"]
        next unless pattern

        if text.match?(Regexp.new(pattern))
          return {
            allowed: !blocking?,
            reason: "Policy '#{name}' output filter matched: #{rule['name']}",
            enforcement: enforcement_level
          }
        end
      end

      { allowed: true, reason: nil }
    end

    # Generic: literal condition matching for custom policy types
    def evaluate_generic(context)
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

    # Count recent agent executions for a given rate limit scope
    def count_executions_for(scope_key, agent_id: nil, user_id: nil)
      window = case scope_key.to_s
               when /per_hour/ then 1.hour.ago
               when /per_day/ then 1.day.ago
               when /per_minute/ then 1.minute.ago
               else return nil
               end

      scope = Ai::AgentExecution.where(account_id: account_id).where("created_at >= ?", window)

      case scope_key.to_s
      when /per_user/
        return nil unless user_id
        scope = scope.where(user_id: user_id)
      when /per_account/
        # account-wide — no additional filter needed
      else
        return nil
      end

      scope.count
    end
  end
end
