# frozen_string_literal: true

# Internal billing API controller for worker service to process billing operations
class Api::V1::Internal::BillingController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/billing/process_renewal
  # Process subscription renewal from worker service
  def process_renewal
    subscription = Subscription.find(params[:subscription_id])

    # Update subscription period
    subscription.update!(
      current_period_start: Time.current,
      current_period_end: calculate_period_end(subscription),
      last_billing_date: Time.current,
      status: params[:status] || "active"
    )

    log_billing_action("process_renewal", subscription)

    render_success(
      data: {
        subscription_id: subscription.id,
        status: subscription.status,
        current_period_end: subscription.current_period_end
      },
      message: "Subscription renewal processed"
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  rescue StandardError => e
    Rails.logger.error "Renewal processing failed: #{e.message}"
    render_error("Failed to process renewal: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/retry_payment
  # Retry failed payment from worker service
  def retry_payment
    subscription = Subscription.find(params[:subscription_id])
    invoice = subscription.invoices.find(params[:invoice_id]) if params[:invoice_id]

    result = {
      success: true,
      subscription_id: subscription.id,
      invoice_id: invoice&.id,
      retried_at: Time.current
    }

    # Record the retry attempt
    subscription.increment!(:payment_retry_count) if subscription.respond_to?(:payment_retry_count)

    log_billing_action("retry_payment", subscription, { invoice_id: invoice&.id })

    render_success(data: result, message: "Payment retry recorded")
  rescue ActiveRecord::RecordNotFound => e
    render_not_found(e.message.include?("Invoice") ? "Invoice" : "Subscription")
  rescue StandardError => e
    Rails.logger.error "Payment retry failed: #{e.message}"
    render_error("Failed to retry payment: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/process_payment
  # Process a payment from worker service
  def process_payment
    invoice = Invoice.find(params[:invoice_id])

    # Create payment record
    payment = invoice.payments.create!(
      account: invoice.account,
      amount: invoice.amount_due,
      status: params[:status] || "completed",
      payment_method_id: params[:payment_method_id],
      processed_at: Time.current,
      metadata: params[:metadata] || {}
    )

    # Update invoice status
    if payment.status == "completed"
      invoice.update!(status: "paid", paid_at: Time.current)
    end

    log_billing_action("process_payment", invoice.subscription, { invoice_id: invoice.id, payment_id: payment.id })

    render_success(
      data: {
        payment_id: payment.id,
        invoice_id: invoice.id,
        status: payment.status,
        amount: payment.amount
      },
      message: "Payment processed"
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Invoice")
  rescue StandardError => e
    Rails.logger.error "Payment processing failed: #{e.message}"
    render_error("Failed to process payment: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/generate_invoice
  # Generate invoice from worker service
  def generate_invoice
    subscription = Subscription.find(params[:subscription_id])

    invoice = subscription.invoices.create!(
      account: subscription.account,
      invoice_number: generate_invoice_number,
      status: "pending",
      amount_due: subscription.plan&.price || 0,
      invoice_type: params[:invoice_type] || "subscription",
      description: params[:description] || "Subscription invoice",
      due_date: 30.days.from_now,
      billing_period_start: subscription.current_period_start,
      billing_period_end: subscription.current_period_end
    )

    log_billing_action("generate_invoice", subscription, { invoice_id: invoice.id })

    render_success(
      data: {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        amount_due: invoice.amount_due,
        status: invoice.status,
        due_date: invoice.due_date
      },
      message: "Invoice generated"
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  rescue StandardError => e
    Rails.logger.error "Invoice generation failed: #{e.message}"
    render_error("Failed to generate invoice: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/suspend_subscription
  # Suspend subscription from worker service (e.g., due to failed payments)
  def suspend_subscription
    subscription = Subscription.find(params[:subscription_id])

    subscription.update!(
      status: "suspended",
      suspended_at: Time.current,
      suspension_reason: params[:reason] || "payment_failure"
    )

    log_billing_action("suspend_subscription", subscription, { reason: params[:reason] })

    render_success(
      data: {
        subscription_id: subscription.id,
        status: subscription.status,
        suspended_at: subscription.suspended_at
      },
      message: "Subscription suspended"
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  rescue StandardError => e
    Rails.logger.error "Suspension failed: #{e.message}"
    render_error("Failed to suspend subscription: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/cancel_subscription
  # Cancel subscription from worker service
  def cancel_subscription
    subscription = Subscription.find(params[:subscription_id])

    subscription.update!(
      status: "cancelled",
      cancelled_at: Time.current,
      cancellation_reason: params[:reason] || "billing_failure"
    )

    log_billing_action("cancel_subscription", subscription, { reason: params[:reason] })

    render_success(
      data: {
        subscription_id: subscription.id,
        status: subscription.status,
        cancelled_at: subscription.cancelled_at
      },
      message: "Subscription cancelled"
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  rescue StandardError => e
    Rails.logger.error "Cancellation failed: #{e.message}"
    render_error("Failed to cancel subscription: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/cleanup
  # Cleanup stale billing data from worker service
  def cleanup
    # Cleanup old invoices, expired trials, etc.
    cleanup_results = {
      stale_invoices_archived: archive_stale_invoices,
      expired_trials_processed: process_expired_trials,
      orphaned_payments_cleaned: cleanup_orphaned_payments,
      cleanup_at: Time.current
    }

    log_billing_action("cleanup", nil, cleanup_results)

    render_success(data: cleanup_results, message: "Billing cleanup completed")
  rescue StandardError => e
    Rails.logger.error "Billing cleanup failed: #{e.message}"
    render_error("Failed to cleanup billing data: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/health_report
  # Report billing system health from worker service
  def health_report
    report = {
      pending_invoices_count: Invoice.where(status: "pending").count,
      overdue_invoices_count: Invoice.where(status: "pending").where("due_date < ?", Time.current).count,
      suspended_subscriptions_count: Subscription.where(status: "suspended").count,
      failed_payments_24h: Payment.where(status: "failed").where("created_at > ?", 24.hours.ago).count,
      processing_queue_size: params[:queue_size] || 0,
      last_successful_renewal: Subscription.where(status: "active").maximum(:updated_at),
      reported_at: Time.current
    }

    # Store health report in cache for monitoring
    Rails.cache.write("billing_health_report", report, expires_in: 1.hour)

    render_success(data: report, message: "Health report recorded")
  rescue StandardError => e
    Rails.logger.error "Health report failed: #{e.message}"
    render_error("Failed to record health report: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/internal/billing/reactivate_suspended_accounts
  # Reactivate suspended accounts after successful payment
  def reactivate_suspended_accounts
    subscription = Subscription.find(params[:subscription_id]) if params[:subscription_id]

    if subscription
      reactivate_subscription(subscription)
      render_success(
        data: { subscription_id: subscription.id, status: subscription.status },
        message: "Subscription reactivated"
      )
    else
      # Batch reactivation for subscriptions with successful recent payments
      reactivated = reactivate_eligible_subscriptions
      render_success(
        data: { reactivated_count: reactivated.count, subscription_ids: reactivated.map(&:id) },
        message: "Eligible subscriptions reactivated"
      )
    end
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  rescue StandardError => e
    Rails.logger.error "Reactivation failed: #{e.message}"
    render_error("Failed to reactivate accounts: #{e.message}", status: :unprocessable_entity)
  end

  private

  def calculate_period_end(subscription)
    case subscription.plan&.billing_cycle
    when "monthly"
      1.month.from_now
    when "quarterly"
      3.months.from_now
    when "yearly"
      1.year.from_now
    else
      1.month.from_now
    end
  end

  def generate_invoice_number
    "INV-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end

  def archive_stale_invoices
    Invoice.where(status: "pending")
           .where("created_at < ?", 90.days.ago)
           .update_all(status: "archived", archived_at: Time.current)
  end

  def process_expired_trials
    Subscription.where(status: "trialing")
                .where("trial_end < ?", Time.current)
                .update_all(status: "past_due")
  end

  def cleanup_orphaned_payments
    # Clean up payments without valid invoices (edge cases)
    0 # Placeholder - implement based on actual cleanup needs
  end

  def reactivate_subscription(subscription)
    subscription.update!(
      status: "active",
      suspended_at: nil,
      suspension_reason: nil
    )
    log_billing_action("reactivate_subscription", subscription)
  end

  def reactivate_eligible_subscriptions
    # Find suspended subscriptions with recent successful payments
    eligible = Subscription.where(status: "suspended")
                           .joins(:payments)
                           .where("payments.status = ? AND payments.created_at > ?", "completed", 24.hours.ago)
                           .distinct

    eligible.each { |sub| reactivate_subscription(sub) }
    eligible
  end

  def log_billing_action(action, subscription, metadata = {})
    AuditLog.create!(
      account: subscription&.account,
      action: "billing.#{action}",
      resource_type: "Subscription",
      resource_id: subscription&.id,
      details: metadata.merge(
        worker_initiated: true,
        timestamp: Time.current.iso8601
      )
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log billing action: #{e.message}"
  end
end
