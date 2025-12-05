# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  before_action :set_subscription, only: [ :show, :update, :destroy ]

  # GET /api/v1/subscriptions
  def index
    subscription = current_account.subscription

    render_success(
      subscription ? [subscription_data(subscription)] : []
    )
  end

  # GET /api/v1/subscriptions/:id
  def show
    render_success(subscription_data(@subscription))
  end

  # POST /api/v1/subscriptions
  def create
    @subscription = current_account.build_subscription(subscription_params)

    if @subscription.save
      render_created(subscription_data(@subscription))
    else
      render_validation_error(@subscription)
    end
  end

  # PATCH/PUT /api/v1/subscriptions/:id
  def update
    if @subscription.update(subscription_update_params)
      render_success(subscription_data(@subscription))
    else
      render_validation_error(@subscription)
    end
  end

  # DELETE /api/v1/subscriptions/:id
  def destroy
    if @subscription.cancel!
      render_no_content
    else
      render_validation_error(@subscription)
    end
  end

  # GET /api/v1/subscriptions/history
  def history
    subscription = current_account.subscription
    
    # Get audit logs related to subscription changes for this account
    audit_logs = AuditLog.where(account: current_account)
                        .where(action: ['create', 'subscription_change', 'update'])
                        .where(resource_type: 'Subscription')
                        .recent
                        .limit(100)
    
    # Also include relevant payment history
    payment_logs = AuditLog.where(account: current_account)
                          .where(action: 'payment')
                          .recent
                          .limit(50)
    
    # Combine and sort by date
    all_logs = (audit_logs.to_a + payment_logs.to_a).sort_by(&:created_at).reverse
    
    history_data = all_logs.map do |log|
      {
        id: log.id,
        event_type: log.metadata.dig('event_type') || log.action,
        action: log.action,
        summary: log.summary,
        changes: log.changes_summary,
        old_values: log.old_values,
        new_values: log.new_values,
        metadata: log.metadata,
        user: log.user ? {
          id: log.user.id,
          name: log.user.full_name,
          email: log.user.email
        } : nil,
        created_at: log.created_at,
        source: log.source
      }
    end

    render_success({
      current_subscription: subscription ? subscription_data(subscription) : nil,
      history: history_data,
      total_events: all_logs.count
    })
  end

  private

  def set_subscription
    @subscription = current_account.subscription

    # Verify the subscription ID matches if provided
    if params[:id] && @subscription&.id != params[:id]
      raise ActiveRecord::RecordNotFound
    end

    raise ActiveRecord::RecordNotFound unless @subscription
  rescue ActiveRecord::RecordNotFound
    render_error("Subscription not found", status: :not_found)
  end

  def subscription_params
    params.require(:subscription).permit(:plan_id, :trial_end)
  end

  def subscription_update_params
    params.require(:subscription).permit(:plan_id)
  end

  def subscription_data(subscription)
    {
      id: subscription.id,
      status: subscription.status,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      trial_ends_at: subscription.trial_end,
      canceled_at: subscription.canceled_at,
      ends_at: subscription.ended_at,
      created_at: subscription.created_at,
      updated_at: subscription.updated_at,
      plan: subscription.plan ? {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price: subscription.plan.price,
        billing_cycle: subscription.plan.billing_cycle,
        features: subscription.plan.features
      } : nil
    }
  end
end
