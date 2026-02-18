# frozen_string_literal: true

module BaaS
  class Subscription < ApplicationRecord
    self.table_name = "baas_subscriptions"

    # Associations
    belongs_to :baas_tenant, class_name: "BaaS::Tenant"
    belongs_to :baas_customer, class_name: "BaaS::Customer"
    has_many :invoices, class_name: "BaaS::Invoice", foreign_key: :baas_subscription_id, dependent: :nullify

    # Validations
    validates :external_id, presence: true, uniqueness: { scope: :baas_tenant_id }
    validates :plan_external_id, presence: true
    validates :status, presence: true, inclusion: { in: %w[incomplete incomplete_expired trialing active past_due canceled unpaid paused] }
    validates :billing_interval, presence: true, inclusion: { in: %w[day week month year] }
    validates :billing_interval_count, numericality: { greater_than: 0 }
    validates :quantity, numericality: { greater_than: 0 }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :trialing, -> { where(status: "trialing") }
    scope :past_due, -> { where(status: "past_due") }
    scope :canceled, -> { where(status: "canceled") }
    scope :with_upcoming_renewal, ->(days) { active.where("current_period_end <= ?", days.days.from_now) }

    # Callbacks
    after_create :increment_tenant_counter
    after_destroy :decrement_tenant_counter

    # Instance methods
    def active?
      status == "active"
    end

    def trialing?
      status == "trialing"
    end

    def canceled?
      status == "canceled"
    end

    def past_due?
      status == "past_due"
    end

    def in_trial?
      trialing? && trial_end.present? && trial_end > Time.current
    end

    def trial_days_remaining
      return 0 unless in_trial?
      ((trial_end - Time.current) / 1.day).ceil
    end

    def cancel!(reason: nil, at_period_end: true)
      if at_period_end
        update!(
          cancel_at_period_end: true,
          cancellation_reason: reason
        )
      else
        update!(
          status: "canceled",
          canceled_at: Time.current,
          ended_at: Time.current,
          cancellation_reason: reason
        )
      end
    end

    def reactivate!
      return false unless cancel_at_period_end && status == "active"
      update!(cancel_at_period_end: false, cancellation_reason: nil)
    end

    def pause!
      return false unless active?
      update!(status: "paused")
    end

    def resume!
      return false unless status == "paused"
      update!(status: "active")
    end

    def advance_billing_period!
      new_start = current_period_end
      new_end = calculate_next_period_end(new_start)

      update!(
        current_period_start: new_start,
        current_period_end: new_end
      )

      # Check if should cancel at period end
      if cancel_at_period_end
        update!(
          status: "canceled",
          canceled_at: Time.current,
          ended_at: Time.current
        )
      end
    end

    def monthly_amount
      return 0 if unit_amount.nil?

      case billing_interval
      when "day" then unit_amount * 30 / billing_interval_count
      when "week" then unit_amount * 4.33 / billing_interval_count
      when "month" then unit_amount / billing_interval_count
      when "year" then unit_amount / 12 / billing_interval_count
      else unit_amount
      end
    end

    def summary
      {
        id: id,
        external_id: external_id,
        customer_id: baas_customer.external_id,
        plan_id: plan_external_id,
        status: status,
        billing_interval: billing_interval,
        billing_interval_count: billing_interval_count,
        unit_amount: unit_amount,
        currency: currency,
        quantity: quantity,
        current_period: {
          start: current_period_start,
          end: current_period_end
        },
        trial_end: trial_end,
        cancel_at_period_end: cancel_at_period_end,
        stripe_subscription_id: stripe_subscription_id,
        created_at: created_at
      }
    end

    private

    def calculate_next_period_end(start_date)
      case billing_interval
      when "day" then start_date + billing_interval_count.days
      when "week" then start_date + billing_interval_count.weeks
      when "month" then start_date + billing_interval_count.months
      when "year" then start_date + billing_interval_count.years
      else start_date + 1.month
      end
    end

    def increment_tenant_counter
      baas_tenant.increment_subscription_count!
    end

    def decrement_tenant_counter
      baas_tenant.decrement_subscription_count!
    end
  end
end
