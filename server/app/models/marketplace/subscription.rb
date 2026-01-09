# frozen_string_literal: true

module Marketplace
  class Subscription < ApplicationRecord
    include Auditable

    # Associations
    belongs_to :account
    belongs_to :app, class_name: "Marketplace::Definition", foreign_key: "app_id"
    belongs_to :plan, class_name: "Marketplace::Plan", foreign_key: "app_plan_id"

    # Validations
    validates :status, presence: true, inclusion: { in: %w[active paused cancelled expired] }
    validates :account_id, uniqueness: { scope: :app_id }
    validates :subscribed_at, presence: true

    # JSON validations
    validates :configuration, presence: true
    validates :usage_metrics, presence: true

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :expired, -> { where(status: "expired") }
    scope :due_for_billing, -> { where("next_billing_at <= ?", Time.current) }
    scope :expiring_soon, -> { where("next_billing_at <= ?", 1.week.from_now) }
    scope :recent, -> { order(subscribed_at: :desc) }
    scope :by_plan, ->(plan) { where(app_plan_id: plan.id) }

    # Callbacks
    before_validation :set_subscription_date, on: :create
    before_save :calculate_next_billing_date
    after_create :log_subscription_created
    after_update :log_status_changes, if: :saved_change_to_status?
    after_update :sync_account_permissions, if: :saved_change_to_status?

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
        revoke_app_permissions
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
        calculate_next_billing_date
        save!
        record_usage_metric("resumed", 1)
        grant_app_permissions
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
        revoke_app_permissions
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
        revoke_app_permissions
        log_subscription_expired
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    # Plan management
    def upgrade_to_plan!(new_plan)
      return false unless new_plan.app == app
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
      return false unless new_plan.app == app
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

    # Usage tracking
    def record_usage_metric(metric_name, value, metadata = {})
      current_metrics = usage_metrics.dup
      current_metrics[metric_name.to_s] = {
        "value" => value,
        "recorded_at" => Time.current.iso8601,
        "metadata" => metadata
      }

      update!(usage_metrics: current_metrics)
    end

    def get_usage_metric(metric_name)
      usage_metrics[metric_name.to_s]
    end

    def usage_within_limits?
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
      limit_value = plan.get_limit(limit_name)
      return Float::INFINITY if limit_value.nil? || limit_value == -1

      current_usage = get_current_usage(limit_name)
      [limit_value - current_usage, 0].max
    end

    def quota_percentage_used(limit_name)
      limit_value = plan.get_limit(limit_name)
      return 0.0 if limit_value.nil? || limit_value == -1

      current_usage = get_current_usage(limit_name)
      return 100.0 if limit_value.zero?

      [(current_usage.to_f / limit_value * 100), 100.0].min
    end

    # Billing methods
    def next_billing_amount
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
      return false unless active? && next_billing_at <= Time.current

      transaction do
        # Record billing event
        record_usage_metric("billing_processed", next_billing_amount)

        # Update next billing date
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
      app.features.where(slug: plan.features)
    end

    def feature_enabled?(feature_slug)
      plan.feature_enabled?(feature_slug)
    end

    def has_permission?(permission)
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

    # Aliases for backward compatibility with old association names
    def app_plan
      plan
    end

    def app_plan=(new_plan)
      self.plan = new_plan
    end

    private

    def set_subscription_date
      self.subscribed_at ||= Time.current
    end

    def calculate_next_billing_date
      return unless active? || paused?

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
        grant_app_permissions
      else
        revoke_app_permissions
      end
    end

    def grant_app_permissions
      # Add app-specific permissions to the account
      plan.permissions.each do |permission|
        # Logic to grant permission to account
        Rails.logger.info "Granting permission #{permission} to account #{account_id} for app #{app.name}"
      end
    end

    def revoke_app_permissions
      # Remove app-specific permissions from the account
      plan.permissions.each do |permission|
        # Logic to revoke permission from account
        Rails.logger.info "Revoking permission #{permission} from account #{account_id} for app #{app.name}"
      end
    end

    def sync_permissions_for_plan_change(old_plan, new_plan)
      # Remove old permissions
      old_plan.permissions.each do |permission|
        unless new_plan.permissions.include?(permission)
          Rails.logger.info "Revoking permission #{permission} from account #{account_id}"
        end
      end

      # Add new permissions
      new_plan.permissions.each do |permission|
        unless old_plan.permissions.include?(permission)
          Rails.logger.info "Granting permission #{permission} to account #{account_id}"
        end
      end
    end

    def log_subscription_created
      Rails.logger.info "App subscription created: Account #{account_id} subscribed to #{app.name} (Plan: #{plan.name})"
    end

    def log_status_changes
      Rails.logger.info "App subscription status changed: #{id} changed to #{status}"
    end

    def log_subscription_paused(reason)
      Rails.logger.info "App subscription paused: #{id} - Reason: #{reason}"
    end

    def log_subscription_resumed
      Rails.logger.info "App subscription resumed: #{id}"
    end

    def log_subscription_cancelled(reason)
      Rails.logger.info "App subscription cancelled: #{id} - Reason: #{reason}"
    end

    def log_subscription_expired
      Rails.logger.info "App subscription expired: #{id}"
    end

    def log_plan_upgrade(old_plan, new_plan)
      Rails.logger.info "App subscription upgraded: #{id} from #{old_plan.name} to #{new_plan.name}"
    end

    def log_plan_downgrade(old_plan, new_plan)
      Rails.logger.info "App subscription downgraded: #{id} from #{old_plan.name} to #{new_plan.name}"
    end

    def log_billing_processed
      Rails.logger.info "Billing processed: #{id} - Amount: #{formatted_next_billing_amount}"
    end
  end
end

# Backward compatibility alias
AppSubscription = Marketplace::Subscription unless defined?(AppSubscription)
