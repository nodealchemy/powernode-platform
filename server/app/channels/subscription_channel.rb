# frozen_string_literal: true

class SubscriptionChannel < ApplicationCable::Channel
  def subscribed
    # Verify user has access to the account
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_for_account(current_account)

      Rails.logger.info "User #{current_user.id} subscribed to subscription updates for account #{account_id}"

      # Send current subscription status on connect
      send_current_subscription_status
    else
      Rails.logger.warn "Unauthorized subscription attempt for account #{account_id} by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from subscription updates"
  end

  # Client can request subscription refresh
  def refresh_subscriptions
    if current_account
      subscription = fetch_subscription_safely

      broadcast_to_account(current_account, {
        type: "subscription_updated",
        subscription: subscription ? serialize_subscription(subscription) : nil
      })
    end
  end

  # Client can request current status
  def get_status
    send_current_subscription_status
  end

  private

  # When the business extension isn't loaded (core-mode install), Account
  # doesn't have a `subscription` association — calling it NoMethodErrors.
  # Treat that the same as "no subscription on this account".
  def fetch_subscription_safely
    return nil unless current_account
    return nil unless ::Shared::FeatureGateService.business_loaded?
    current_account.respond_to?(:subscription) ? current_account.subscription : nil
  end

  def send_current_subscription_status
    return unless current_account

    subscription = fetch_subscription_safely

    data = {
      type: "subscription_status",
      subscription: subscription ? serialize_subscription(subscription) : nil,
      account_id: current_account.id,
      timestamp: Time.current.iso8601
    }

    transmit(data)
  end

  def serialize_subscription(subscription)
    {
      id: subscription.id,
      status: subscription.status,
      current_period_start: subscription.current_period_start&.iso8601,
      current_period_end: subscription.current_period_end&.iso8601,
      trial_ends_at: subscription.trial_end&.iso8601,
      canceled_at: subscription.canceled_at&.iso8601,
      ends_at: subscription.ended_at&.iso8601,
      created_at: subscription.created_at.iso8601,
      updated_at: subscription.updated_at.iso8601,
      plan: subscription.plan ? {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price: subscription.plan.price_cents,
        interval: subscription.plan.billing_cycle,
        features: subscription.plan.features,
        currency: subscription.plan.currency
      } : nil
    }
  end
end
