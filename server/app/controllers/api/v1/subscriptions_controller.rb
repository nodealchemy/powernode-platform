# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  before_action :set_subscription, only: [ :show, :update, :destroy, :pause, :resume, :preview_proration ]

  # GET /api/v1/subscriptions
  def index
    return render_error("No account associated with user", status: :unauthorized) unless current_account

    subscription = current_account.subscription

    render_success(
      subscription ? [ subscription_data(subscription) ] : []
    )
  end

  # GET /api/v1/subscriptions/:id
  def show
    render_success(subscription_data(@subscription))
  end

  # POST /api/v1/subscriptions
  def create
    return render_error("No account associated with user", status: :unauthorized) unless current_account

    @subscription = current_account.build_subscription(subscription_params)

    if @subscription.save
      render_created(subscription_data(@subscription))
    else
      render_validation_error(@subscription)
    end
  end

  # PATCH/PUT /api/v1/subscriptions/:id
  def update
    new_plan_id = params.dig(:subscription, :plan_id)

    # If changing plans, calculate and include proration data
    if new_plan_id.present? && new_plan_id != @subscription.plan_id
      new_plan = Plan.find_by(id: new_plan_id)

      unless new_plan
        return render_error("Plan not found", status: :not_found)
      end

      unless new_plan.active?
        return render_error("Selected plan is not available", status: :unprocessable_entity)
      end

      old_plan = @subscription.plan

      # Calculate proration if we have billing period dates
      proration = nil
      if @subscription.current_period_end.present?
        service = Billing::SubscriptionService.new(@subscription)
        proration = service.calculate_proration(
          old_plan: old_plan,
          new_plan: new_plan,
          billing_cycle_anchor: @subscription.current_period_end,
          current_period_start: @subscription.current_period_start
        )
      end

      ActiveRecord::Base.transaction do
        @subscription.update!(subscription_update_params)

        # Store plan change details in metadata for billing processing
        plan_change_data = {
          "old_plan_id" => old_plan.id,
          "new_plan_id" => new_plan.id,
          "changed_at" => Time.current.iso8601
        }
        plan_change_data["proration"] = proration if proration.present?

        @subscription.update!(
          metadata: @subscription.metadata.merge("last_plan_change" => plan_change_data)
        )
      end

      response_data = subscription_data(@subscription.reload)
      response_data[:proration] = proration if proration.present?

      is_upgrade = new_plan.price_cents > old_plan.price_cents
      render_success(
        response_data,
        message: is_upgrade ? "Subscription upgraded successfully" : "Subscription downgraded successfully"
      )
    elsif @subscription.update(subscription_update_params)
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

  # POST /api/v1/subscriptions/:id/pause
  def pause
    unless @subscription.may_pause?
      return render_error(
        "Subscription cannot be paused from current status: #{@subscription.status}",
        status: :unprocessable_entity
      )
    end

    pause_reason = params[:reason] || "User requested pause"

    ActiveRecord::Base.transaction do
      @subscription.pause!
      @subscription.update!(
        metadata: @subscription.metadata.merge(
          "paused_at" => Time.current.iso8601,
          "pause_reason" => pause_reason,
          "paused_by_user_id" => current_user.id
        )
      )
    end

    render_success(
      subscription_data(@subscription.reload),
      message: "Subscription paused successfully"
    )
  rescue AASM::InvalidTransition => e
    render_error("Failed to pause subscription: #{e.message}", status: :unprocessable_entity)
  end

  # POST /api/v1/subscriptions/:id/resume
  def resume
    unless @subscription.may_resume?
      return render_error(
        "Subscription cannot be resumed from current status: #{@subscription.status}",
        status: :unprocessable_entity
      )
    end

    ActiveRecord::Base.transaction do
      @subscription.resume!
      @subscription.update!(
        metadata: @subscription.metadata.merge(
          "resumed_at" => Time.current.iso8601,
          "resumed_by_user_id" => current_user.id
        ).except("paused_at", "pause_reason", "paused_by_user_id")
      )
    end

    render_success(
      subscription_data(@subscription.reload),
      message: "Subscription resumed successfully"
    )
  rescue AASM::InvalidTransition => e
    render_error("Failed to resume subscription: #{e.message}", status: :unprocessable_entity)
  end

  # GET /api/v1/subscriptions/:id/preview_proration
  def preview_proration
    new_plan_id = params[:new_plan_id]

    unless new_plan_id.present?
      return render_error("new_plan_id parameter is required", status: :bad_request)
    end

    new_plan = Plan.find_by(id: new_plan_id)

    unless new_plan
      return render_error("Plan not found", status: :not_found)
    end

    unless new_plan.active?
      return render_error("Selected plan is not available", status: :unprocessable_entity)
    end

    old_plan = @subscription.plan

    if old_plan.id == new_plan.id
      return render_error("Cannot prorate to the same plan", status: :unprocessable_entity)
    end

    unless @subscription.current_period_end.present?
      return render_error("Cannot calculate proration: subscription has no billing period end date", status: :unprocessable_entity)
    end

    service = Billing::SubscriptionService.new(@subscription)
    proration = service.calculate_proration(
      old_plan: old_plan,
      new_plan: new_plan,
      billing_cycle_anchor: @subscription.current_period_end,
      current_period_start: @subscription.current_period_start
    )

    render_success({
      current_plan: {
        id: old_plan.id,
        name: old_plan.name,
        price_cents: old_plan.price_cents,
        billing_cycle: old_plan.billing_cycle
      },
      new_plan: {
        id: new_plan.id,
        name: new_plan.name,
        price_cents: new_plan.price_cents,
        billing_cycle: new_plan.billing_cycle
      },
      proration: proration,
      effective_date: Date.current.iso8601,
      billing_cycle_end: @subscription.current_period_end&.iso8601
    })
  end

  # GET /api/v1/subscriptions/by_stripe_id
  def by_stripe_id
    unless params[:stripe_id].present?
      return render_error("stripe_id parameter is required", status: :bad_request)
    end

    subscription = Subscription.find_by(stripe_subscription_id: params[:stripe_id])

    if subscription
      render_success(data: subscription_data(subscription))
    else
      render_error("Subscription not found with Stripe ID: #{params[:stripe_id]}", status: :not_found)
    end
  end

  # GET /api/v1/subscriptions/by_paypal_id
  def by_paypal_id
    unless params[:paypal_id].present?
      return render_error("paypal_id parameter is required", status: :bad_request)
    end

    subscription = Subscription.find_by(paypal_subscription_id: params[:paypal_id])

    if subscription
      render_success(data: subscription_data(subscription))
    else
      render_error("Subscription not found with PayPal ID: #{params[:paypal_id]}", status: :not_found)
    end
  end

  # GET /api/v1/subscriptions/history
  def history
    return render_error("No account associated with user", status: :unauthorized) unless current_account

    subscription = current_account.subscription

    # Get audit logs related to subscription changes for this account
    audit_logs = AuditLog.where(account: current_account)
                        .where(action: [ "create", "subscription_change", "update" ])
                        .where(resource_type: "Subscription")
                        .recent
                        .limit(100)

    # Also include relevant payment history
    payment_logs = AuditLog.where(account: current_account)
                          .where(action: "payment")
                          .recent
                          .limit(50)

    # Combine and sort by date
    all_logs = (audit_logs.to_a + payment_logs.to_a).sort_by(&:created_at).reverse

    history_data = all_logs.map do |log|
      {
        id: log.id,
        event_type: log.metadata.dig("event_type") || log.action,
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
    # Guard against nil current_account
    unless current_account
      return render_error("No account associated with user", status: :unauthorized)
    end

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
