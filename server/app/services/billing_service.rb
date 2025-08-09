class BillingService
  include ActiveModel::Model

  attr_accessor :subscription, :account, :user

  def initialize(subscription)
    @subscription = subscription
    @account = subscription.account
    @user = subscription.account.users.first
  end

  # Create subscription with payment method
  def create_subscription_with_payment(plan:, payment_method:, trial_end: nil, quantity: 1, **options)
    ActiveRecord::Base.transaction do
      # Create subscription
      subscription = account.subscriptions.create!(
        plan: plan,
        quantity: quantity,
        trial_end: trial_end || (plan.trial_days.days.from_now if plan.trial_days > 0),
        current_period_start: Time.current,
        current_period_end: calculate_period_end(plan, trial_end),
        status: trial_end || plan.trial_days > 0 ? "trialing" : "active",
        metadata: options
      )

      # Create subscription in payment gateway
      case payment_method.provider
      when "stripe"
        create_stripe_subscription(subscription, payment_method, options)
      when "paypal"
        create_paypal_subscription(subscription, payment_method, options)
      end

      # Generate initial invoice if not in trial
      unless subscription.on_trial?
        generate_subscription_invoice(subscription)
      end

      subscription
    end
  end

  # Generate subscription invoice
  def generate_subscription_invoice(custom_subscription = nil)
    sub = custom_subscription || subscription

    invoice = sub.invoices.create!(
      subtotal_cents: calculate_subscription_amount(sub),
      tax_rate: account.tax_rate || 0.0,
      currency: sub.plan.currency,
      due_date: 30.days.from_now
    )

    # Add subscription line item
    invoice.add_subscription_line_item(sub.plan, sub.quantity)

    # Add usage-based charges if applicable
    add_usage_charges(invoice, sub) if sub.plan.has_usage_pricing?

    # Add any pending one-time charges
    add_pending_charges(invoice, sub)

    # Calculate totals and finalize
    invoice.calculate_totals
    invoice.finalize!

    invoice
  end

  # Handle subscription changes (upgrades/downgrades)
  def change_subscription(new_plan:, quantity: nil, prorate: true, effective_date: nil)
    effective_date ||= Time.current
    quantity ||= subscription.quantity

    ActiveRecord::Base.transaction do
      old_plan = subscription.plan
      old_quantity = subscription.quantity

      # Calculate proration if needed
      proration_credit = 0
      proration_charge = 0

      if prorate && !subscription.on_trial?
        proration_credit = calculate_proration_credit(subscription, effective_date)
        proration_charge = calculate_proration_charge(new_plan, quantity, effective_date)
      end

      # Update subscription
      subscription.update!(
        plan: new_plan,
        quantity: quantity,
        metadata: subscription.metadata.merge(
          previous_plan_id: old_plan.id,
          changed_at: effective_date.iso8601
        )
      )

      # Update in payment gateway
      case subscription.payment_provider
      when "stripe"
        update_stripe_subscription(subscription, new_plan, quantity, prorate)
      when "paypal"
        update_paypal_subscription(subscription, new_plan, quantity)
      end

      # Generate proration invoice if needed
      if prorate && (proration_credit != 0 || proration_charge != 0)
        generate_proration_invoice(subscription, proration_credit, proration_charge, old_plan, new_plan)
      end

      subscription
    end
  end

  # Cancel subscription
  def cancel_subscription(at_period_end: true, reason: nil)
    cancellation_date = at_period_end ? subscription.current_period_end : Time.current

    subscription.cancel!
    subscription.update!(
      canceled_at: Time.current,
      ended_at: cancellation_date,
      metadata: subscription.metadata.merge(
        cancellation_reason: reason,
        at_period_end: at_period_end
      )
    )

    case subscription.payment_provider
    when "stripe"
      cancel_stripe_subscription(subscription, at_period_end)
    when "paypal"
      cancel_paypal_subscription(subscription, reason)
    end
  end

  # Handle failed payment
  def handle_failed_payment(payment)
    # Schedule retry attempts with exponential backoff
    retry_schedule = [ 1.day, 3.days, 5.days, 7.days ]

    retry_schedule.each_with_index do |delay, index|
      # Schedule background job for payment retry
      PaymentRetryJob.set(wait: delay).perform_later(payment.id, index + 1)
    end

    # Mark subscription as past due after first failure
    subscription.mark_past_due! if subscription.may_mark_past_due?

    # Send dunning emails
    send_dunning_notification(payment, "payment_failed")
  end

  # Process payment retry
  def retry_failed_payment(payment, retry_attempt)
    return false if retry_attempt > 4

    payment_processor = PaymentProcessingService.new(
      account: account,
      user: user
    )

    result = payment_processor.retry_payment(payment: payment)

    if result[:success]
      Rails.logger.info "Payment retry successful: #{payment.id} (attempt #{retry_attempt})"
      true
    else
      Rails.logger.warn "Payment retry failed: #{payment.id} (attempt #{retry_attempt})"

      # Final retry attempt - suspend subscription
      if retry_attempt >= 4
        suspend_subscription_for_non_payment
        send_dunning_notification(payment, "final_payment_failure")
      end

      false
    end
  end

  private

  def calculate_period_end(plan, trial_end)
    start_date = trial_end || Time.current

    case plan.billing_cycle
    when "monthly"
      start_date + 1.month
    when "quarterly"
      start_date + 3.months
    when "yearly"
      start_date + 1.year
    else
      start_date + 1.month
    end
  end

  def calculate_subscription_amount(sub)
    base_amount = sub.plan.price_cents * sub.quantity

    # Add setup fees if first billing period
    if sub.invoices.count == 0 && sub.plan.setup_fee_cents > 0
      base_amount += sub.plan.setup_fee_cents
    end

    base_amount
  end

  def add_usage_charges(invoice, sub)
    # Implementation for usage-based billing would go here
  end

  def add_pending_charges(invoice, sub)
    # Implementation for pending one-time charges would go here
  end

  def calculate_proration_credit(sub, effective_date)
    return 0 if sub.on_trial?

    remaining_days = ((sub.current_period_end - effective_date) / 1.day).ceil
    total_days = ((sub.current_period_end - sub.current_period_start) / 1.day).ceil

    return 0 if remaining_days <= 0

    current_amount = sub.plan.price_cents * sub.quantity
    (current_amount * remaining_days / total_days.to_f).round
  end

  def calculate_proration_charge(new_plan, quantity, effective_date)
    return 0 unless subscription.current_period_end

    remaining_days = ((subscription.current_period_end - effective_date) / 1.day).ceil
    total_days = ((subscription.current_period_end - subscription.current_period_start) / 1.day).ceil

    return 0 if remaining_days <= 0

    new_amount = new_plan.price_cents * quantity
    (new_amount * remaining_days / total_days.to_f).round
  end

  def generate_proration_invoice(sub, credit, charge, old_plan, new_plan)
    net_amount = charge - credit
    return if net_amount == 0

    invoice = sub.invoices.create!(
      subtotal_cents: net_amount.abs,
      tax_rate: account.tax_rate || 0.0,
      currency: sub.plan.currency,
      due_date: 1.day.from_now,
      invoice_type: "proration"
    )

    if credit > 0
      invoice.add_line_item(
        description: "Credit for unused time on #{old_plan.name}",
        quantity: 1,
        unit_price_cents: -credit
      )
    end

    if charge > 0
      invoice.add_line_item(
        description: "Prorated charge for #{new_plan.name}",
        quantity: 1,
        unit_price_cents: charge
      )
    end

    invoice.calculate_totals
    invoice.finalize! if net_amount > 0
  end

  def suspend_subscription_for_non_payment
    subscription.mark_unpaid! if subscription.may_mark_unpaid?

    account.update!(
      status: "suspended",
      suspended_at: Time.current,
      suspension_reason: "non_payment"
    )
  end

  def send_dunning_notification(payment, notification_type)
    # Implementation for sending dunning emails would go here
    Rails.logger.info "Dunning notification: #{notification_type} for payment #{payment.id}"
  end

  # Stripe-specific methods
  def create_stripe_subscription(sub, payment_method, options)
    customer = ensure_stripe_customer

    stripe_sub = Stripe::Subscription.create({
      customer: customer.id,
      items: [ { price: sub.plan.stripe_price_id, quantity: sub.quantity } ],
      payment_behavior: "default_incomplete",
      default_payment_method: payment_method.provider_payment_method_id,
      trial_end: sub.trial_end&.to_i,
      metadata: {
        account_id: account.id,
        subscription_id: sub.id
      }
    }.merge(options))

    sub.update!(stripe_subscription_id: stripe_sub.id)
    stripe_sub
  end

  def update_stripe_subscription(sub, new_plan, quantity, prorate)
    Stripe::Subscription.update(sub.stripe_subscription_id, {
      items: [ {
        id: get_stripe_subscription_item_id(sub),
        price: new_plan.stripe_price_id,
        quantity: quantity
      } ],
      proration_behavior: prorate ? "create_prorations" : "none"
    })
  end

  def cancel_stripe_subscription(sub, at_period_end)
    Stripe::Subscription.delete(sub.stripe_subscription_id, {
      prorate: !at_period_end
    })
  end

  # PayPal-specific methods (placeholder implementations)
  def create_paypal_subscription(sub, payment_method, options)
    # PayPal subscription creation would go here
    Rails.logger.info "PayPal subscription creation not fully implemented"
  end

  def update_paypal_subscription(sub, new_plan, quantity)
    # PayPal subscription update would go here
    Rails.logger.info "PayPal subscription update not fully implemented"
  end

  def cancel_paypal_subscription(sub, reason)
    # PayPal subscription cancellation would go here
    Rails.logger.info "PayPal subscription cancellation not fully implemented"
  end

  # Helper methods
  def ensure_stripe_customer
    return @stripe_customer if @stripe_customer

    if account.stripe_customer_id.present?
      @stripe_customer = Stripe::Customer.retrieve(account.stripe_customer_id)
    else
      @stripe_customer = Stripe::Customer.create({
        email: user.email,
        name: user.full_name,
        metadata: {
          account_id: account.id,
          user_id: user.id
        }
      })

      account.update!(stripe_customer_id: @stripe_customer.id)
    end

    @stripe_customer
  end

  def get_stripe_subscription_item_id(sub)
    stripe_sub = Stripe::Subscription.retrieve(sub.stripe_subscription_id)
    stripe_sub.items.data.first.id
  end
end
