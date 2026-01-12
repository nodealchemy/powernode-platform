# frozen_string_literal: true

class SubscriptionBroadcastService
  def self.broadcast_subscription_updated(subscription)
    new(subscription).broadcast_updated
  end

  def self.broadcast_subscription_created(subscription)
    new(subscription).broadcast_created
  end

  def self.broadcast_subscription_cancelled(subscription)
    new(subscription).broadcast_cancelled
  end

  def self.broadcast_trial_ending(subscription)
    new(subscription).broadcast_trial_ending
  end

  def self.broadcast_payment_processed(payment)
    subscription = payment.subscription
    new(subscription).broadcast_payment_processed(payment)
  end

  def initialize(subscription)
    @subscription = subscription
    @account = subscription.account
  end

  def broadcast_updated
    broadcast_to_account({
      type: "subscription_updated",
      subscription: serialize_subscription,
      message: "Subscription has been updated",
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_created
    broadcast_to_account({
      type: "subscription_created",
      subscription: serialize_subscription,
      message: "New subscription created",
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_cancelled
    broadcast_to_account({
      type: "subscription_cancelled",
      subscription: serialize_subscription,
      message: "Subscription has been cancelled",
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_trial_ending
    days_left = (@subscription.trial_end - Time.current).to_i / 1.day

    broadcast_to_account({
      type: "trial_ending",
      subscription: serialize_subscription,
      message: "Trial ending in #{days_left} day#{'s' if days_left != 1}",
      days_remaining: days_left,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_payment_processed(payment)
    broadcast_to_account({
      type: "payment_processed",
      subscription: serialize_subscription,
      payment: {
        id: payment.id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        status: payment.status,
        processed_at: payment.processed_at&.iso8601
      },
      message: "Payment processed successfully",
      timestamp: Time.current.iso8601
    })
  end

  private

  attr_reader :subscription, :account

  def broadcast_to_account(data)
    ActionCable.server.broadcast("account_#{account.id}", data)
  end

  def serialize_subscription
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
