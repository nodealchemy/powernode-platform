# frozen_string_literal: true

module Marketplace
  class Subscription < ApplicationRecord
    include Auditable

    # Polymorphic association for unified marketplace subscriptions
    belongs_to :subscribable, polymorphic: true, optional: true

    # Legacy associations (optional for backward compatibility with apps)
    belongs_to :account
    belongs_to :app, class_name: "Marketplace::Definition", foreign_key: "app_id", optional: true
    belongs_to :plan, class_name: "Marketplace::Plan", foreign_key: "app_plan_id", optional: true

    # Validations
    validates :status, presence: true, inclusion: { in: %w[active paused cancelled expired] }
    validates :subscribed_at, presence: true
    validates :tier, inclusion: { in: %w[free standard premium enterprise] }, allow_nil: true
    validate :validate_subscribable_or_app

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
    scope :by_plan, ->(plan) { where(app_plan_id: plan.id) }

    # Scopes - Type filtering (polymorphic) - Feature template types
    scope :for_workflow_templates, -> { where(subscribable_type: "Ai::WorkflowTemplate") }
    scope :for_pipeline_templates, -> { where(subscribable_type: "Devops::PipelineTemplate") }
    scope :for_integration_templates, -> { where(subscribable_type: "Devops::IntegrationTemplate") }
    scope :for_prompt_templates, -> { where(subscribable_type: "Shared::PromptTemplate") }

    # Legacy scopes for backward compatibility
    scope :for_apps, -> { where(subscribable_type: "Marketplace::Definition") }

    scope :for_type, ->(type) {
      case type.to_s
      when "workflow_template" then for_workflow_templates
      when "pipeline_template" then for_pipeline_templates
      when "integration_template" then for_integration_templates
      when "prompt_template" then for_prompt_templates
      # Legacy types
      when "app" then for_apps
      when "template" then for_workflow_templates  # Alias for backward compatibility
      when "integration" then for_integration_templates
      else none
      end
    }

    # Callbacks
    before_validation :set_subscription_date, on: :create
    before_validation :sync_subscribable_from_app, on: :create
    before_save :calculate_next_billing_date, if: :has_plan?
    after_create :log_subscription_created
    after_update :log_status_changes, if: :saved_change_to_status?
    after_update :sync_account_permissions, if: -> { saved_change_to_status? && has_plan? }

    # Type checking methods - Feature template types
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

    # Legacy type checking methods
    def app_subscription?
      subscribable_type == "Marketplace::Definition"
    end

    # Alias for backward compatibility
    def template_subscription?
      workflow_template_subscription?
    end

    def subscription_type
      case subscribable_type
      when "Ai::WorkflowTemplate" then "workflow_template"
      when "Devops::PipelineTemplate" then "pipeline_template"
      when "Devops::IntegrationTemplate" then "integration_template"
      when "Shared::PromptTemplate" then "prompt_template"
      # Legacy types
      when "Marketplace::Definition" then "app"
      else "unknown"
      end
    end

    # Unified item accessor
    def item
      subscribable || app
    end

    def item_name
      subscribable&.name || app&.name
    end

    def item_slug
      subscribable&.slug || app&.slug
    end

    def item_icon
      case subscribable_type
      when "Ai::WorkflowTemplate", "Devops::PipelineTemplate"
        subscribable&.icon_url
      when "Devops::IntegrationTemplate"
        subscribable&.icon_url
      else
        nil
      end
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
        revoke_permissions if has_plan?
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
        calculate_next_billing_date if has_plan?
        save!
        record_usage_metric("resumed", 1)
        grant_permissions if has_plan?
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
        revoke_permissions if has_plan?
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
        revoke_permissions if has_plan?
        log_subscription_expired
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Plan management (for app subscriptions)
    def upgrade_to_plan!(new_plan)
      return false unless app_subscription?
      return false unless new_plan.app == (subscribable || app)
      return false unless active?

      old_plan = plan
      transaction do
        update!(app_plan_id: new_plan.id)
        calculate_next_billing_date
        save!
        sync_permissions_for_plan_change(old_plan, new_plan)
        record_usage_metric("plan_upgraded", 1, {
          old_plan: old_plan.slug,
          new_plan: new_plan.slug
        })
        log_plan_upgrade(old_plan, new_plan)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def downgrade_to_plan!(new_plan)
      return false unless app_subscription?
      return false unless new_plan.app == (subscribable || app)
      return false unless active?

      old_plan = plan
      transaction do
        update!(app_plan_id: new_plan.id)
        calculate_next_billing_date
        save!
        sync_permissions_for_plan_change(old_plan, new_plan)
        record_usage_metric("plan_downgraded", 1, {
          old_plan: old_plan.slug,
          new_plan: new_plan.slug
        })
        log_plan_downgrade(old_plan, new_plan)
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Tier management (for non-app subscriptions)
    def upgrade_tier!(new_tier)
      return false if app_subscription?
      return false unless %w[free standard premium enterprise].include?(new_tier)
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

    def usage_within_limits?
      return true unless has_plan?

      plan.limits.all? do |limit_name, limit_value|
        next true if limit_value == -1 # Unlimited
        current_usage = get_current_usage(limit_name)
        current_usage <= limit_value
      end
    end

    def get_current_usage(limit_name)
      metric = get_usage_metric("#{limit_name}_usage")
      metric&.dig("value") || 0
    end

    def remaining_quota(limit_name)
      return Float::INFINITY unless has_plan?

      limit_value = plan.get_limit(limit_name)
      return Float::INFINITY if limit_value.nil? || limit_value == -1

      current_usage = get_current_usage(limit_name)
      [limit_value - current_usage, 0].max
    end

    def quota_percentage_used(limit_name)
      return 0.0 unless has_plan?

      limit_value = plan.get_limit(limit_name)
      return 0.0 if limit_value.nil? || limit_value == -1

      current_usage = get_current_usage(limit_name)
      return 100.0 if limit_value.zero?

      [(current_usage.to_f / limit_value * 100), 100.0].min
    end

    # Billing methods
    def next_billing_amount
      return 0 unless has_plan?
      plan.price_cents
    end

    def formatted_next_billing_amount
      "$#{next_billing_amount / 100.0}"
    end

    def days_until_billing
      return nil unless next_billing_at
      ((next_billing_at - Time.current) / 1.day).round
    end

    def process_billing!
      return false unless has_plan?
      return false unless active? && next_billing_at <= Time.current

      transaction do
        record_usage_metric("billing_processed", next_billing_amount)
        calculate_next_billing_date
        save!
        log_billing_processed
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Permission management
    def enabled_features
      return [] unless has_plan? && app_subscription?
      (subscribable || app).features.where(slug: plan.features)
    end

    def feature_enabled?(feature_slug)
      return false unless has_plan?
      plan.feature_enabled?(feature_slug)
    end

    def has_permission?(permission)
      return false unless has_plan?
      plan.has_permission?(permission)
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

    def total_amount_paid
      billing_metrics = usage_metrics.select { |k, _| k.include?("billing_processed") }
      billing_metrics.sum { |_, data| data["value"] || 0 }
    end

    def average_monthly_usage(metric_name)
      usage_data = usage_metrics.select { |k, _| k.include?(metric_name) }
      return 0.0 if usage_data.empty?

      total_usage = usage_data.sum { |_, data| data["value"] || 0 }
      months = [subscription_age_in_days / 30.0, 1].max
      (total_usage / months).round(2)
    end

    # Helper methods
    def has_plan?
      plan.present?
    end

    # Aliases for backward compatibility
    def app_plan
      plan
    end

    def app_plan=(new_plan)
      self.plan = new_plan
    end

    private

    def validate_subscribable_or_app
      if subscribable_id.blank? && app_id.blank?
        errors.add(:base, "must have either a subscribable item or an app")
      end
    end

    def sync_subscribable_from_app
      # For backward compatibility: if app_id is set but subscribable is not, set it
      if app_id.present? && subscribable_id.blank?
        self.subscribable_type = "Marketplace::Definition"
        self.subscribable_id = app_id
      end
    end

    def set_subscription_date
      self.subscribed_at ||= Time.current
    end

    def calculate_next_billing_date
      return unless has_plan? && (active? || paused?)

      case plan.billing_interval
      when "monthly"
        self.next_billing_at = (subscribed_at || Time.current) + 1.month
      when "yearly"
        self.next_billing_at = (subscribed_at || Time.current) + 1.year
      when "one_time"
        self.next_billing_at = nil
      end
    end

    def sync_account_permissions
      if active?
        grant_permissions
      else
        revoke_permissions
      end
    end

    def grant_permissions
      return unless has_plan?
      plan.permissions.each do |permission|
        Rails.logger.info "Granting permission #{permission} to account #{account_id} for #{item_name}"
      end
    end

    def revoke_permissions
      return unless has_plan?
      plan.permissions.each do |permission|
        Rails.logger.info "Revoking permission #{permission} from account #{account_id} for #{item_name}"
      end
    end

    def sync_permissions_for_plan_change(old_plan, new_plan)
      old_plan.permissions.each do |permission|
        unless new_plan.permissions.include?(permission)
          Rails.logger.info "Revoking permission #{permission} from account #{account_id}"
        end
      end

      new_plan.permissions.each do |permission|
        unless old_plan.permissions.include?(permission)
          Rails.logger.info "Granting permission #{permission} to account #{account_id}"
        end
      end
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

    def log_plan_upgrade(old_plan, new_plan)
      Rails.logger.info "Marketplace subscription upgraded: #{id} from #{old_plan.name} to #{new_plan.name}"
    end

    def log_plan_downgrade(old_plan, new_plan)
      Rails.logger.info "Marketplace subscription downgraded: #{id} from #{old_plan.name} to #{new_plan.name}"
    end

    def log_billing_processed
      Rails.logger.info "Billing processed: #{id} - Amount: #{formatted_next_billing_amount}"
    end
  end
end

# Backward compatibility alias
AppSubscription = Marketplace::Subscription unless defined?(AppSubscription)
