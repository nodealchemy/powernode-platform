# Billing Automation Configuration
Rails.application.configure do
  # Billing automation configuration
  config.powernode = config.respond_to?(:powernode) ? config.powernode : ActiveSupport::OrderedOptions.new
  config.powernode.billing = ActiveSupport::OrderedOptions.new

  # Payment retry configuration
  config.powernode.billing.max_payment_retries = 4
  config.powernode.billing.retry_schedule = [ 1.day, 3.days, 5.days, 7.days ]

  # Grace periods
  config.powernode.billing.trial_grace_period_days = 3
  config.powernode.billing.payment_grace_period_days = 7

  # Dunning configuration
  config.powernode.billing.dunning_enabled = true
  config.powernode.billing.dunning_sequence = [
    { days: 1, type: "soft_dunning" },
    { days: 3, type: "hard_dunning" },
    { days: 7, type: "final_dunning" }
  ]

  # Notification configuration
  config.powernode.billing.send_notifications = true
  config.powernode.billing.admin_alerts_enabled = true

  # Cleanup configuration
  config.powernode.billing.cleanup_failed_payments_after_days = 90
  config.powernode.billing.void_invoices_after_days = 60
  config.powernode.billing.cleanup_cancelled_accounts_after_days = 30
end

# Initialize billing automation after Rails loads
Rails.application.config.after_initialize do
  # Only schedule jobs in production or when explicitly enabled
  if Rails.env.production? || ENV["ENABLE_BILLING_AUTOMATION"] == "true"
    Rails.logger.info "Initializing billing automation system"

    begin
      # Schedule daily billing scheduler
      WorkerJobService.enqueue_billing_scheduler(Date.current, delay: 1.hour)

      # Schedule weekly cleanup
      WorkerJobService.enqueue_billing_cleanup(delay: 1.day)

      # Schedule immediate billing check if there are overdue subscriptions
      overdue_count = Subscription.joins(:account)
                                 .where(status: [ "active", "trialing", "past_due" ])
                                 .where("current_period_end < ?", Time.current)
                                 .where(accounts: { status: "active" })
                                 .count

      if overdue_count > 0
        Rails.logger.info "Found #{overdue_count} overdue subscriptions, scheduling immediate billing automation"
        WorkerJobService.enqueue_billing_automation(nil, delay: 1.minute)
      end

      Rails.logger.info "Billing automation system initialized successfully"

    rescue => e
      Rails.logger.error "Failed to initialize billing automation: #{e.message}"
      # Don't raise error to prevent application startup failure
    end
  else
    Rails.logger.info "Billing automation disabled (not in production and ENABLE_BILLING_AUTOMATION not set)"
  end
end

# Helper method to manually trigger billing automation
class BillingAutomation
  class << self
    def trigger_billing_cycle(subscription_id = nil)
      if subscription_id
        WorkerJobService.enqueue_billing_automation(subscription_id)
      else
        WorkerJobService.enqueue_billing_automation
      end
    end

    def trigger_payment_retry(payment_id, retry_attempt = 1)
      WorkerJobService.enqueue_payment_retry(payment_id, "payment_failure", retry_attempt)
    end

    def trigger_lifecycle_action(action, subscription_id, **options)
      WorkerJobService.enqueue_subscription_lifecycle(action, subscription_id, **options)
    end

    def force_billing_cleanup
      WorkerJobService.enqueue_billing_cleanup
    end

    def get_billing_health_report
      Rails.cache.read("billing_health_report")
    end

    def get_subscription_metrics
      Rails.cache.read("subscription_metrics")
    end
  end
end
