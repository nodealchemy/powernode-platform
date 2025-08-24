# frozen_string_literal: true

require_relative '../base_job'

# Converted from BillingCleanupJob to use API-only connectivity
# Handles billing system maintenance and cleanup tasks
class Billing::BillingCleanupJob < BaseJob
  sidekiq_options queue: 'maintenance',
                  retry: 1

  def execute
    logger.info "Starting billing cleanup and maintenance"
    
    begin
      # Clean up old failed payments
      cleanup_old_failed_payments
      
      # Clean up expired invoices
      cleanup_expired_invoices
      
      # Update subscription metrics
      update_subscription_metrics
      
      # Cleanup orphaned payment methods
      cleanup_orphaned_payment_methods
      
      # Update account suspension status
      update_account_suspension_status
      
      # Generate billing health report
      generate_billing_health_report
      
      logger.info "Billing cleanup completed successfully"
      
    rescue StandardError => e
      logger.error "Billing cleanup failed: #{e.message}"
      raise
    end
  end

  private

  def cleanup_old_failed_payments
    # Request cleanup of old failed payments via API
    cutoff_date = 90.days.ago
    cleanup_params = {
      type: 'failed_payments',
      cutoff_date: cutoff_date.iso8601
    }
    
    result = with_api_retry do
      api_client.post('/api/v1/billing/cleanup', cleanup_params)
    end
    
    logger.info "Cleaned up #{result['count']} old failed payments"
  end

  def cleanup_expired_invoices
    # Request cleanup of expired invoices via API
    cutoff_date = 60.days.ago
    cleanup_params = {
      type: 'expired_invoices',
      cutoff_date: cutoff_date.iso8601
    }
    
    result = with_api_retry do
      api_client.post('/api/v1/billing/cleanup', cleanup_params)
    end
    
    logger.info "Marked #{result['count']} invoices as expired"
  end

  def update_subscription_metrics
    # Request subscription metrics update via API
    metrics_result = with_api_retry do
      api_client.post('/api/v1/analytics/update_metrics', { type: 'subscription_metrics' })
    end
    
    logger.info "Updated subscription metrics cache"
    logger.info "Active subscriptions by plan: #{metrics_result['active_by_plan']&.size || 0} plans"
  end

  def cleanup_orphaned_payment_methods
    # Request cleanup of orphaned payment methods via API
    cutoff_date = 30.days.ago
    cleanup_params = {
      type: 'orphaned_payment_methods',
      cutoff_date: cutoff_date.iso8601
    }
    
    result = with_api_retry do
      api_client.post('/api/v1/billing/cleanup', cleanup_params)
    end
    
    logger.info "Cleaned up #{result['count']} orphaned payment methods"
  end

  def update_account_suspension_status
    # Request account suspension status updates via API
    result = with_api_retry do
      api_client.post('/api/v1/billing/reactivate_suspended_accounts')
    end
    
    if result['reactivated_count'] > 0
      logger.info "Reactivated #{result['reactivated_count']} accounts after payment resolution"
    end
    
    result['reactivated_accounts']&.each do |account|
      send_account_reactivation_notification(account)
    end
  end

  def generate_billing_health_report
    # Request billing health report generation via API
    report_result = with_api_retry do
      api_client.post('/api/v1/billing/health_report')
    end
    
    report_data = report_result['report']
    
    logger.info "Generated billing health report"
    logger.info "Payment success rate: #{report_data['payment_success_rate']}"
    logger.info "Churn rate: #{report_data.dig('subscription_health', 'churn_rate')}"
    
    # Send alert if there are issues
    if report_data['payment_success_rate'] < 0.95 || 
       report_data.dig('subscription_health', 'churn_rate') > 0.10
      send_billing_health_alert(report_data)
    end
  end

  def send_account_reactivation_notification(account)
    notification_params = {
      type: 'account_reactivated',
      account_id: account['id'],
      message: 'Account reactivated after payment method update',
      severity: 'info'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent account reactivation notification for account #{account['id']}"
  rescue StandardError => e
    logger.error "Failed to send account reactivation notification: #{e.message}"
  end

  def send_billing_health_alert(report_data)
    alert_params = {
      type: 'billing_health_alert',
      message: 'Billing system health issues detected',
      severity: 'critical',
      admin_alert: true,
      metadata: {
        payment_success_rate: report_data['payment_success_rate'],
        churn_rate: report_data.dig('subscription_health', 'churn_rate'),
        report_timestamp: Time.current.iso8601
      }
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', alert_params)
    end
    
    logger.warn "ADMIN ALERT: Billing health issues detected"
    logger.warn "Payment success rate: #{report_data['payment_success_rate']}"
    logger.warn "Churn rate: #{report_data.dig('subscription_health', 'churn_rate')}"
  rescue StandardError => e
    logger.error "Failed to send billing health alert: #{e.message}"
  end
end