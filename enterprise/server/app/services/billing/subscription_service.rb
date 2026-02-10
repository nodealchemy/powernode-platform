# frozen_string_literal: true

module Billing
  # Subscription Service - Delegates complex operations to worker service
  class SubscriptionService
    include ActiveModel::Model

    attr_accessor :subscription, :account, :user

    def initialize(subscription = nil)
      @subscription = subscription
      @account = subscription&.account
      @user = subscription&.account&.users&.first
    end

    # Create subscription with payment method (delegated to worker service)
    def create_subscription_with_payment(plan:, payment_method:, trial_end: nil, quantity: 1, **options)
      Rails.logger.info "Delegating subscription creation to worker service"

      job_data = {
        plan_id: plan.id,
        payment_method_id: payment_method.id,
        account_id: account.id,
        user_id: user.id,
        trial_end: trial_end,
        quantity: quantity
      }.merge(options)

      begin
        # Enqueue job in worker service for complex billing logic
        WorkerJobService.enqueue_billing_job("create_subscription_with_payment", job_data)

        # Return immediate response - actual processing happens asynchronously
        {
          success: true,
          message: "Subscription creation queued for processing",
          job_data: job_data
        }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate billing job: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Process subscription renewal (delegated to worker service)
    def process_renewal(subscription_id: nil, payment_retry_attempt: 0)
      subscription_id ||= subscription&.id

      unless subscription_id
        return { success: false, error: "No subscription specified" }
      end

      Rails.logger.info "Delegating renewal processing to worker service"

      job_data = {
        subscription_id: subscription_id,
        payment_retry_attempt: payment_retry_attempt
      }

      begin
        # Enqueue renewal job in worker service
        WorkerJobService.enqueue_billing_job("process_renewal", job_data)

        {
          success: true,
          message: "Renewal processing queued",
          subscription_id: subscription_id
        }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate renewal job: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Cancel subscription (delegated to worker service)
    def cancel_subscription(cancellation_reason: nil, immediate: false)
      unless subscription
        return { success: false, error: "No subscription to cancel" }
      end

      Rails.logger.info "Delegating subscription cancellation to worker service"

      job_data = {
        subscription_id: subscription.id,
        cancellation_reason: cancellation_reason,
        immediate: immediate
      }

      begin
        # Enqueue cancellation job in worker service
        WorkerJobService.enqueue_billing_job("cancel_subscription", job_data)

        {
          success: true,
          message: "Cancellation queued for processing",
          subscription_id: subscription.id
        }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate cancellation job: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Suspend subscription (delegated to worker service)
    def suspend_subscription(suspension_reason: nil)
      unless subscription
        return { success: false, error: "No subscription to suspend" }
      end

      Rails.logger.info "Delegating subscription suspension to worker service"

      job_data = {
        subscription_id: subscription.id,
        suspension_reason: suspension_reason
      }

      begin
        # Enqueue suspension job in worker service
        WorkerJobService.enqueue_billing_job("suspend_subscription", job_data)

        {
          success: true,
          message: "Suspension queued for processing",
          subscription_id: subscription.id
        }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate suspension job: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Simple synchronous operations that don't need worker delegation
    def calculate_proration(old_plan:, new_plan:, billing_cycle_anchor:, current_period_start: nil)
      # Use current_period_start if provided, otherwise use current date
      period_start = current_period_start || Date.current
      billing_anchor = billing_cycle_anchor.to_date

      # Calculate days remaining in the current billing period
      days_remaining = (billing_anchor - Date.current).to_i
      return { proration_amount_cents: 0, days_remaining: 0, proration_factor: 0.0 } if days_remaining <= 0

      # Calculate actual calendar days in the billing period
      days_in_period = calculate_actual_billing_period_days(new_plan.billing_cycle, period_start)
      return { proration_amount_cents: 0, days_remaining: 0, proration_factor: 0.0 } if days_in_period <= 0

      proration_factor = days_remaining.to_f / days_in_period

      # Calculate prorated amounts
      new_amount = new_plan.price_cents * proration_factor
      old_refund = old_plan.price_cents * proration_factor

      # Net proration: positive means customer owes more, negative means credit
      proration_amount = (new_amount - old_refund).round

      {
        proration_amount_cents: proration_amount,
        days_remaining: days_remaining,
        days_in_period: days_in_period,
        proration_factor: proration_factor.round(4),
        new_plan_prorated_cents: new_amount.round,
        old_plan_credit_cents: old_refund.round,
        is_upgrade: new_plan.price_cents > old_plan.price_cents
      }
    end

    # Calculate actual calendar days in a billing period
    def calculate_actual_billing_period_days(billing_cycle, start_date)
      start_date = start_date.to_date if start_date.respond_to?(:to_date)

      case billing_cycle
      when "monthly"
        # Use actual days in the month (handles Feb, 30/31 day months)
        ((start_date >> 1) - start_date).to_i
      when "quarterly"
        # Use actual days in 3 months
        ((start_date >> 3) - start_date).to_i
      when "yearly"
        # Use actual days in the year (handles leap years: 365 or 366)
        ((start_date >> 12) - start_date).to_i
      else
        # Fallback to standard 30 days
        30
      end
    end

    def format_currency(amount_cents)
      Money.new(amount_cents, "USD").format
    end

    # Class methods for direct worker service delegation
    class << self
      def process_all_renewals(force: false)
        Rails.logger.info "Delegating bulk renewal processing to worker service"

        begin
          WorkerJobService.enqueue_billing_job("process_all_renewals", { force: force })
          { success: true, message: "Bulk renewal processing queued" }
        rescue WorkerJobService::WorkerServiceError => e
          Rails.logger.error "Failed to delegate bulk renewals: #{e.message}"
          { success: false, error: e.message }
        end
      end

      def cleanup_expired_subscriptions
        Rails.logger.info "Delegating subscription cleanup to worker service"

        begin
          WorkerJobService.enqueue_billing_job("cleanup_expired_subscriptions", {})
          { success: true, message: "Cleanup processing queued" }
        rescue WorkerJobService::WorkerServiceError => e
          Rails.logger.error "Failed to delegate cleanup: #{e.message}"
          { success: false, error: e.message }
        end
      end

      def generate_billing_report(account_id: nil, start_date: nil, end_date: nil)
        Rails.logger.info "Delegating billing report generation to worker service"

        job_data = {
          account_id: account_id,
          start_date: start_date,
          end_date: end_date,
          report_type: "billing_summary"
        }

        begin
          WorkerJobService.enqueue_report_job("generate_report", job_data)
          { success: true, message: "Report generation queued", job_data: job_data }
        rescue WorkerJobService::WorkerServiceError => e
          Rails.logger.error "Failed to delegate report generation: #{e.message}"
          { success: false, error: e.message }
        end
      end
    end
  end
end
