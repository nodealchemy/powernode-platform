# frozen_string_literal: true

# Dunning process job for handling failed payment retries
class Billing::DunningProcessJob < BaseJob
  sidekiq_options queue: 'billing', retry: 2

  DUNNING_STAGES = {
    1 => { delay: 3.days, action: 'first_reminder' },
    2 => { delay: 7.days, action: 'second_reminder' },
    3 => { delay: 14.days, action: 'final_notice' },
    4 => { delay: 21.days, action: 'suspend_account' }
  }.freeze

  def execute(subscription_id, reason = 'payment_failure', dunning_stage = 1)
    validate_required_params(subscription_id: subscription_id)

    log_info "Running dunning process for subscription #{subscription_id}, stage #{dunning_stage}"

    # Fetch subscription details from backend
    subscription_response = api_client.get("/api/v1/internal/subscriptions/#{subscription_id}")

    unless subscription_response['success']
      log_error "Failed to fetch subscription: #{subscription_response['error']}"
      raise BillingExceptions::SubscriptionError.new(
        subscription_response['error'] || 'Failed to fetch subscription',
        subscription_id: subscription_id,
        action: 'dunning_fetch'
      )
    end

    subscription_data = subscription_response['data']
    account_id = subscription_data['account_id']
    dunning_config = DUNNING_STAGES[dunning_stage]

    unless dunning_config
      log_error "Invalid dunning stage: #{dunning_stage}"
      raise BillingExceptions::ValidationError.new(
        "Invalid dunning stage: #{dunning_stage}",
        field: 'dunning_stage',
        value: dunning_stage
      )
    end

    # Execute dunning action via API
    result = execute_dunning_action(
      subscription_id,
      account_id,
      dunning_config[:action],
      dunning_stage,
      reason
    )

    if result[:success]
      log_info "Dunning action #{dunning_config[:action]} completed successfully"

      # Schedule next dunning stage if not suspended
      if dunning_stage < 4
        schedule_next_dunning(subscription_id, reason, dunning_stage + 1, dunning_config[:delay])
      end

      { success: true, action: dunning_config[:action], next_stage: dunning_stage + 1 }
    else
      log_error "Dunning action failed: #{result[:error]}"
      raise BillingExceptions::DunningError.new(
        result[:error] || 'Dunning action failed',
        subscription_id: subscription_id,
        attempt: dunning_stage
      )
    end
  rescue BillingExceptions::BillingError
    # Re-raise billing exceptions for Sidekiq retry
    raise
  rescue StandardError => e
    log_error "Dunning process job failed: #{e.message}"
    raise BillingExceptions::DunningError.new(
      "Dunning process failed: #{e.message}",
      subscription_id: subscription_id,
      attempt: dunning_stage,
      details: { original_error: e.class.name }
    )
  end

  private

  def execute_dunning_action(subscription_id, account_id, action, stage, reason)
    response = with_api_retry do
      api_client.post("/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
        action: action,
        stage: stage,
        reason: reason,
        account_id: account_id
      })
    end

    if response['success']
      { success: true, data: response['data'] }
    else
      { success: false, error: response['error'] || 'Dunning action failed' }
    end
  end

  def schedule_next_dunning(subscription_id, reason, next_stage, delay)
    log_info "Scheduling next dunning stage #{next_stage} in #{delay} seconds"

    Billing::DunningProcessJob.perform_in(delay, subscription_id, reason, next_stage)
  rescue StandardError => e
    log_error "Failed to schedule next dunning: #{e.message}"
  end
end
