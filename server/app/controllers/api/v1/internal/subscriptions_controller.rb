# frozen_string_literal: true

# Internal API controller for worker service to manage subscriptions
class Api::V1::Internal::SubscriptionsController < Api::V1::Internal::InternalBaseController
  before_action :set_subscription, only: [ :show, :dunning ]

  # GET /api/v1/internal/subscriptions/:id
  def show
    render_success(data: subscription_data(@subscription))
  end

  # POST /api/v1/internal/subscriptions/:id/dunning
  def dunning
    # Process dunning for the subscription
    @subscription.update(dunning_status: params[:dunning_status] || "active")

    render_success(
      data: subscription_data(@subscription),
      message: "Dunning status updated"
    )
  end

  private

  def set_subscription
    @subscription = Subscription.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Subscription")
  end

  def subscription_data(subscription)
    {
      id: subscription.id,
      account_id: subscription.account_id,
      plan_id: subscription.plan_id,
      status: subscription.status,
      current_period_start: subscription.current_period_start,
      current_period_end: subscription.current_period_end,
      cancel_at_period_end: subscription.cancel_at_period_end,
      created_at: subscription.created_at,
      updated_at: subscription.updated_at
    }
  end
end
