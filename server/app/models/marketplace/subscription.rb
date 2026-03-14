# frozen_string_literal: true

module Marketplace
  class Subscription < ApplicationRecord
    include Auditable

    self.table_name = "marketplace_subscriptions"

    # Polymorphic association for unified marketplace subscriptions
    belongs_to :subscribable, polymorphic: true
    belongs_to :account

    # Validations
    validates :status, presence: true, inclusion: { in: %w[active paused cancelled expired] }
    validates :subscribed_at, presence: true
    validates :tier, inclusion: { in: %w[free standard premium business] }, allow_nil: true
    validate :validate_subscribable

    # JSON attributes
    attribute :configuration, :json, default: -> { {} }
    attribute :usage_metrics, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes - Status
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :expired, -> { where(status: "expired") }

    # Scopes - Billing
    scope :due_for_billing, -> { where("next_billing_at <= ?", Time.current) }
    scope :expiring_soon, -> { where("next_billing_at <= ?", 1.week.from_now) }

    # Scopes - Ordering
    scope :recent, -> { order(subscribed_at: :desc) }

    # Scopes - Type filtering (polymorphic)
    scope :for_workflow_templates, -> { where(subscribable_type: "Ai::WorkflowTemplate") }
    scope :for_pipeline_templates, -> { where(subscribable_type: "Devops::PipelineTemplate") }
    scope :for_integration_templates, -> { where(subscribable_type: "Devops::IntegrationTemplate") }
    scope :for_prompt_templates, -> { where(subscribable_type: "Shared::PromptTemplate") }

    scope :for_type, ->(type) {
      case type.to_s
      when "workflow_template", "template" then for_workflow_templates
      when "pipeline_template" then for_pipeline_templates
      when "integration_template", "integration" then for_integration_templates
      when "prompt_template" then for_prompt_templates
      else none
      end
    }

    # Callbacks
    before_validation :set_subscription_date, on: :create
    after_create :log_subscription_created
    after_update :log_status_changes, if: :saved_change_to_status?

    # Type checking methods
    def workflow_template_subscription?
      subscribable_type == "Ai::WorkflowTemplate"
    end

    def pipeline_template_subscription?
      subscribable_type == "Devops::PipelineTemplate"
    end

    def integration_template_subscription?
      subscribable_type == "Devops::IntegrationTemplate"
    end

    def prompt_template_subscription?
      subscribable_type == "Shared::PromptTemplate"
    end

    def template_subscription?
      workflow_template_subscription?
    end

    def subscription_type
      case subscribable_type
      when "Ai::WorkflowTemplate" then "workflow_template"
      when "Devops::PipelineTemplate" then "pipeline_template"
      when "Devops::IntegrationTemplate" then "integration_template"
      when "Shared::PromptTemplate" then "prompt_template"
      else "unknown"
      end
    end

    # Unified item accessor
    def item
      subscribable
    end

    def item_name
      subscribable&.name
    end

    def item_slug
      subscribable&.slug
    end

    def item_icon
      subscribable&.try(:icon_url)
    end

    # Status methods
    def active?
      status == "active"
    end

    def paused?
      status == "paused"
    end

    def cancelled?
      status == "cancelled"
    end

    def expired?
      status == "expired"
    end

    # Subscription management
    def pause!(reason = nil)
      return false unless active?

      transaction do
        update!(status: "paused", cancelled_at: Time.current)
        record_usage_metric("paused", 1, { reason: reason })
        log_subscription_paused(reason)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def resume!
      return false unless paused?

      transaction do
        update!(status: "active", cancelled_at: nil)
        record_usage_metric("resumed", 1)
        log_subscription_resumed
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def cancel!(reason = nil)
      return false if cancelled? || expired?

      transaction do
        update!(status: "cancelled", cancelled_at: Time.current)
        record_usage_metric("cancelled", 1, { reason: reason })
        log_subscription_cancelled(reason)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def expire!
      return false unless active?

      transaction do
        update!(status: "expired", cancelled_at: Time.current)
        record_usage_metric("expired", 1)
        log_subscription_expired
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Tier management
    def upgrade_tier!(new_tier)
      return false unless %w[free standard premium business].include?(new_tier)
      return false unless active?

      old_tier = tier
      transaction do
        update!(tier: new_tier)
        record_usage_metric("tier_upgraded", 1, { old_tier: old_tier, new_tier: new_tier })
        update_metadata("tier_changed_at", Time.current.iso8601)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Usage tracking
    def record_usage_metric(metric_name, value, extra_metadata = {})
      current_metrics = usage_metrics.dup
      current_metrics[metric_name.to_s] = {
        "value" => value,
        "recorded_at" => Time.current.iso8601,
        "metadata" => extra_metadata
      }
      update!(usage_metrics: current_metrics)
    end

    def get_usage_metric(metric_name)
      usage_metrics[metric_name.to_s]
    end

    def get_current_usage(limit_name)
      metric = get_usage_metric("#{limit_name}_usage")
      metric&.dig("value") || 0
    end

    def usage_within_limits?
      # With templates/integrations, usage is always within limits
      # unless specific tier limits are configured
      true
    end

    # Billing methods
    def days_until_billing
      return nil unless next_billing_at
      ((next_billing_at - Time.current) / 1.day).round
    end

    # Configuration methods
    def get_config(key)
      configuration[key.to_s]
    end

    def set_config(key, value)
      self.configuration = configuration.merge(key.to_s => value)
      save!
    end

    def merge_config(new_config)
      self.configuration = configuration.merge(new_config.stringify_keys)
      save!
    end

    # Metadata methods
    def get_metadata(key)
      metadata[key.to_s]
    end

    def update_metadata(key, value)
      self.metadata = metadata.merge(key.to_s => value)
      save!
    end

    # Analytics methods
    def subscription_age_in_days
      ((Time.current - subscribed_at) / 1.day).round
    end

    def average_monthly_usage(metric_name)
      usage_data = usage_metrics.select { |k, _| k.include?(metric_name) }
      return 0.0 if usage_data.empty?

      total_usage = usage_data.sum { |_, data| data["value"] || 0 }
      months = [ subscription_age_in_days / 30.0, 1 ].max
      (total_usage / months).round(2)
    end

    private

    def validate_subscribable
      errors.add(:subscribable, "must be present") if subscribable_id.blank?
    end

    def set_subscription_date
      self.subscribed_at ||= Time.current
    end

    def log_subscription_created
      Rails.logger.info "Marketplace subscription created: Account #{account_id} subscribed to #{item_name} (Type: #{subscription_type})"
    end

    def log_status_changes
      Rails.logger.info "Marketplace subscription status changed: #{id} changed to #{status}"
    end

    def log_subscription_paused(reason)
      Rails.logger.info "Marketplace subscription paused: #{id} - Reason: #{reason}"
    end

    def log_subscription_resumed
      Rails.logger.info "Marketplace subscription resumed: #{id}"
    end

    def log_subscription_cancelled(reason)
      Rails.logger.info "Marketplace subscription cancelled: #{id} - Reason: #{reason}"
    end

    def log_subscription_expired
      Rails.logger.info "Marketplace subscription expired: #{id}"
    end
  end
end
