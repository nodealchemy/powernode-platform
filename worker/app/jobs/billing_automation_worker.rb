require_relative 'base_job'

# Job for handling billing automation tasks
class BillingAutomationWorker < BaseJob
  sidekiq_options queue: 'billing', retry: 5, backtrace: true

  def execute(task_type, *args)
    case task_type
    when 'process_renewals'
      process_subscription_renewals
    when 'generate_invoices'
      generate_invoices_for_date(args[0])
    when 'process_dunning'
      process_dunning_management(args[0])
    when 'update_trial_status'
      update_trial_subscriptions
    else
      log_error("Unknown billing automation task", nil, task_type: task_type)
    end
  end

  private

  def process_subscription_renewals
    log_info("Processing subscription renewals")
    
    begin
      # Get subscriptions due for renewal
      subscriptions = api_client.get_subscription_data(status: 'active')
      
      if subscriptions[:success]
        renewal_count = 0
        
        subscriptions[:data].each do |subscription|
          if subscription_due_for_renewal?(subscription)
            process_subscription_renewal(subscription)
            renewal_count += 1
          end
        end
        
        log_info("Processed subscription renewals", processed: renewal_count)
      else
        log_error("Failed to fetch subscriptions for renewal")
      end
      
    rescue ApiClient::ApiError => e
      handle_api_error(e, task: 'process_renewals')
    rescue => e
      log_error("Unexpected error processing renewals", e)
      raise
    end
  end

  def generate_invoices_for_date(target_date)
    target_date = Date.parse(target_date) if target_date.is_a?(String)
    log_info("Generating invoices", date: target_date)
    
    begin
      subscriptions = api_client.get_subscription_data(status: 'active')
      
      if subscriptions[:success]
        invoice_count = 0
        
        subscriptions[:data].each do |subscription|
          if should_generate_invoice?(subscription, target_date)
            generate_invoice_for_subscription(subscription)
            invoice_count += 1
          end
        end
        
        log_info("Generated invoices", count: invoice_count, date: target_date)
      end
      
    rescue ApiClient::ApiError => e
      handle_api_error(e, task: 'generate_invoices', date: target_date)
    rescue => e
      log_error("Unexpected error generating invoices", e, date: target_date)
      raise
    end
  end

  def process_dunning_management(account_id = nil)
    log_info("Processing dunning management", account_id: account_id)
    
    begin
      # Get failed/past due invoices
      invoices = api_client.get_invoice_data(
        account_id: account_id,
        status: 'past_due'
      )
      
      if invoices[:success]
        processed_count = 0
        
        invoices[:data].each do |invoice|
          process_dunning_for_invoice(invoice)
          processed_count += 1
        end
        
        log_info("Processed dunning management", processed: processed_count)
      end
      
    rescue ApiClient::ApiError => e
      handle_api_error(e, task: 'process_dunning', account_id: account_id)
    rescue => e
      log_error("Unexpected error processing dunning", e, account_id: account_id)
      raise
    end
  end

  def update_trial_subscriptions
    log_info("Updating trial subscription statuses")
    
    begin
      # Get trialing subscriptions
      subscriptions = api_client.get_subscription_data(status: 'trialing')
      
      if subscriptions[:success]
        updated_count = 0
        
        subscriptions[:data].each do |subscription|
          if trial_expired?(subscription)
            update_expired_trial(subscription)
            updated_count += 1
          end
        end
        
        log_info("Updated trial subscriptions", updated: updated_count)
      end
      
    rescue ApiClient::ApiError => e
      handle_api_error(e, task: 'update_trial_status')
    rescue => e
      log_error("Unexpected error updating trials", e)
      raise
    end
  end

  def subscription_due_for_renewal?(subscription)
    return false unless subscription[:current_period_end]
    
    end_date = Time.parse(subscription[:current_period_end])
    end_date <= Time.now
  end

  def should_generate_invoice?(subscription, target_date)
    return false unless subscription[:current_period_start]
    
    period_start = Date.parse(subscription[:current_period_start])
    period_start == target_date
  end

  def trial_expired?(subscription)
    return false unless subscription[:trial_end]
    
    trial_end = Time.parse(subscription[:trial_end])
    trial_end <= Time.now
  end

  def process_subscription_renewal(subscription)
    log_info("Processing renewal", subscription_id: subscription[:id])
    
    # Update subscription period
    new_period_start = Time.parse(subscription[:current_period_end])
    new_period_end = calculate_next_period_end(new_period_start, subscription[:plan][:billing_cycle])
    
    api_client.update_subscription_status(subscription[:id], 'active', {
      current_period_start: new_period_start.utc.iso8601,
      current_period_end: new_period_end.utc.iso8601
    })
    
    create_audit_log(
      account_id: subscription[:account_id],
      action: 'renew',
      resource_type: 'Subscription',
      resource_id: subscription[:id],
      metadata: { 
        previous_period_end: subscription[:current_period_end],
        new_period_end: new_period_end.utc.iso8601
      }
    )
  end

  def generate_invoice_for_subscription(subscription)
    log_info("Generating invoice", subscription_id: subscription[:id])
    
    line_items = [{
      description: "#{subscription[:plan][:name]} - Monthly Subscription",
      quantity: subscription[:quantity],
      unit_price_cents: subscription[:plan][:price_cents],
      total_cents: subscription[:plan][:price_cents] * subscription[:quantity],
      period_start: subscription[:current_period_start],
      period_end: subscription[:current_period_end]
    }]
    
    result = api_client.create_invoice(subscription[:id], line_items)
    
    if result[:success]
      create_audit_log(
        account_id: subscription[:account_id],
        action: 'create',
        resource_type: 'Invoice',
        resource_id: result[:data][:id],
        metadata: { 
          subscription_id: subscription[:id],
          amount_cents: subscription[:plan][:price_cents] * subscription[:quantity]
        }
      )
    end
  end

  def process_dunning_for_invoice(invoice)
    log_info("Processing dunning", invoice_id: invoice[:id])
    
    # Calculate days overdue
    due_date = Date.parse(invoice[:due_date])
    days_overdue = (Date.today - due_date).to_i
    
    # Apply dunning logic based on days overdue
    case days_overdue
    when 1..3
      # Send reminder email
      log_info("Sending payment reminder", invoice_id: invoice[:id], days_overdue: days_overdue)
    when 7..10
      # Send urgent payment notice
      log_info("Sending urgent payment notice", invoice_id: invoice[:id], days_overdue: days_overdue)
    when 14..30
      # Suspend account access
      log_info("Suspending account access", invoice_id: invoice[:id], days_overdue: days_overdue)
      api_client.update_subscription_status(invoice[:subscription_id], 'past_due')
    when 30..Float::INFINITY
      # Cancel subscription
      log_info("Canceling subscription", invoice_id: invoice[:id], days_overdue: days_overdue)
      api_client.update_subscription_status(invoice[:subscription_id], 'canceled')
    end
  end

  def update_expired_trial(subscription)
    log_info("Updating expired trial", subscription_id: subscription[:id])
    
    api_client.update_subscription_status(subscription[:id], 'active', {
      trial_end: nil,
      current_period_start: Time.now.utc.iso8601,
      current_period_end: calculate_next_period_end(Time.now, subscription[:plan][:billing_cycle]).utc.iso8601
    })
    
    create_audit_log(
      account_id: subscription[:account_id],
      action: 'convert_trial',
      resource_type: 'Subscription', 
      resource_id: subscription[:id],
      metadata: { 
        trial_end: subscription[:trial_end]
      }
    )
  end

  def calculate_next_period_end(start_time, billing_cycle)
    case billing_cycle
    when 'monthly'
      start_time + (30 * 24 * 60 * 60) # 30 days
    when 'yearly'
      start_time + (365 * 24 * 60 * 60) # 365 days
    when 'quarterly'
      start_time + (90 * 24 * 60 * 60) # 90 days
    else
      start_time + (30 * 24 * 60 * 60) # Default to 30 days
    end
  end
end