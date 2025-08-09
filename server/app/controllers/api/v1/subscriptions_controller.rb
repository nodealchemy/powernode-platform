# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  before_action :set_subscription, only: [ :show, :update, :destroy ]

  # GET /api/v1/subscriptions
  def index
    subscription = current_account.subscription

    render json: {
      success: true,
      data: subscription ? [subscription_data(subscription)] : []
    }, status: :ok
  end

  # GET /api/v1/subscriptions/:id
  def show
    render json: {
      success: true,
      data: subscription_data(@subscription)
    }, status: :ok
  end

  # POST /api/v1/subscriptions
  def create
    @subscription = current_account.build_subscription(subscription_params)

    if @subscription.save
      render json: {
        success: true,
        data: subscription_data(@subscription),
        message: "Subscription created successfully"
      }, status: :created
    else
      render json: {
        success: false,
        error: "Subscription creation failed",
        details: @subscription.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/subscriptions/:id
  def update
    if @subscription.update(subscription_update_params)
      render json: {
        success: true,
        data: subscription_data(@subscription),
        message: "Subscription updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Subscription update failed",
        details: @subscription.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/subscriptions/:id
  def destroy
    if @subscription.cancel!
      render json: {
        success: true,
        message: "Subscription cancelled successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Subscription cancellation failed",
        details: @subscription.errors.full_messages
      }, status: :unprocessable_content
    end
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
    render json: {
      success: false,
      error: "Subscription not found"
    }, status: :not_found
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
