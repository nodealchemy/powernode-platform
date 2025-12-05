# frozen_string_literal: true

class Api::V1::AppSubscriptionsController < ApplicationController
  include AuditLogging
  
  before_action :set_subscription, only: [:show, :update, :destroy, :pause, :resume, :cancel, :upgrade_plan, :downgrade_plan, :usage, :analytics]
  before_action :set_app, only: [:create]
  before_action :authorize_subscription_access, only: [:show, :update, :destroy, :pause, :resume, :cancel, :upgrade_plan, :downgrade_plan, :usage, :analytics]
  
  def index
    subscriptions = current_account.app_subscriptions.includes(:app, :app_plan)
    
    # Apply status filters
    case params[:status]
    when 'active'
      subscriptions = subscriptions.active
    when 'paused'
      subscriptions = subscriptions.paused
    when 'cancelled'
      subscriptions = subscriptions.cancelled
    when 'expired'
      subscriptions = subscriptions.expired
    end
    
    # Apply pagination
    pagination = pagination_params
    page = pagination[:page]
    per_page = pagination[:per_page]
    
    # Get total count before applying limit/offset
    total_count = subscriptions.count
    total_pages = (total_count.to_f / per_page).ceil
    
    # Apply pagination
    subscriptions = subscriptions.limit(per_page).offset((page - 1) * per_page)
    
    render_success(
      data: subscriptions.map { |subscription| subscription_data(subscription) },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: per_page
      }
    )
  end
  
  def active
    subscriptions = current_account.app_subscriptions.active.includes(:app, :app_plan)

    render_success(subscriptions.map { |subscription| subscription_data(subscription) })
  end
  
  def cancelled
    subscriptions = current_account.app_subscriptions.cancelled.includes(:app, :app_plan)

    render_success(subscriptions.map { |subscription| subscription_data(subscription) })
  end
  
  def expired
    subscriptions = current_account.app_subscriptions.expired.includes(:app, :app_plan)

    render_success(subscriptions.map { |subscription| subscription_data(subscription) })
  end
  
  def show
    render_success(subscription_data(@subscription, detailed: true))
  end
  
  def create
    plan = @app.app_plans.find_by(id: params[:app_plan_id])
    return render_error('App plan not found', status: :not_found) unless plan
    
    # Check if subscription already exists
    existing = current_account.app_subscriptions.find_by(app: @app)
    if existing&.active?
      return render_error('Already subscribed to this app', status: :conflict)
    end
    
    @subscription = current_account.app_subscriptions.build(
      app: @app,
      app_plan: plan,
      status: 'active',
      configuration: subscription_params[:configuration] || {},
      usage_metrics: {}
    )

    if @subscription.save
      log_resource_created(@subscription,
                           metadata: { app_name: @app.name, plan_name: plan.name },
                           severity: 'medium')
      Rails.logger.info "App subscription created: Account #{current_account.id} subscribed to #{@app.name}"

      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Successfully subscribed to app',
        status: :created
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def update
    old_attributes = @subscription.attributes.slice('status', 'configuration')

    if @subscription.update(subscription_update_params)
      log_resource_updated(@subscription, old_attributes, severity: 'medium')
      Rails.logger.info "App subscription updated: #{@subscription.id}"

      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Subscription updated successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def destroy
    subscription_id = @subscription.id
    app_name = @subscription.app.name

    if @subscription.destroy
      log_resource_deleted(@subscription,
                           metadata: { app_name: app_name },
                           severity: 'high')
      Rails.logger.info "App subscription deleted: #{subscription_id} for app #{app_name}"

      render_success(message: 'Subscription deleted successfully')
    else
      render_validation_error(@subscription)
    end
  end
  
  def pause
    reason = params[:reason]
    
    if @subscription.pause!(reason)
      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Subscription paused successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def resume
    if @subscription.resume!
      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Subscription resumed successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def cancel
    reason = params[:reason]
    
    if @subscription.cancel!(reason)
      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Subscription cancelled successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def upgrade_plan
    new_plan = @subscription.app.app_plans.find_by(id: params[:app_plan_id])
    return render_error('App plan not found', status: :not_found) unless new_plan
    
    if @subscription.upgrade_to_plan!(new_plan)
      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Plan upgraded successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def downgrade_plan
    new_plan = @subscription.app.app_plans.find_by(id: params[:app_plan_id])
    return render_error('App plan not found', status: :not_found) unless new_plan
    
    if @subscription.downgrade_to_plan!(new_plan)
      render_success(
        data: subscription_data(@subscription, detailed: true),
        message: 'Plan downgraded successfully'
      )
    else
      render_validation_error(@subscription)
    end
  end
  
  def usage
    usage_data = {
      current_period_usage: @subscription.usage_metrics,
      limits: @subscription.app_plan.limits,
      quota_usage: {},
      remaining_quotas: {},
      billing_info: {
        next_billing_at: @subscription.next_billing_at,
        next_billing_amount: @subscription.formatted_next_billing_amount,
        days_until_billing: @subscription.days_until_billing
      }
    }
    
    # Calculate quota usage for each limit
    @subscription.app_plan.limits.each_key do |limit_name|
      usage_data[:quota_usage][limit_name] = @subscription.quota_percentage_used(limit_name)
      usage_data[:remaining_quotas][limit_name] = @subscription.remaining_quota(limit_name)
    end
    
    render_success(usage_data)
  end
  
  def analytics
    analytics_data = {
      subscription_age_days: @subscription.subscription_age_in_days,
      total_amount_paid: @subscription.total_amount_paid,
      average_monthly_usage: {},
      usage_trends: @subscription.usage_metrics,
      feature_usage: @subscription.enabled_features.map { |feature|
        {
          slug: feature.slug,
          name: feature.name,
          usage_count: @subscription.get_usage_metric("#{feature.slug}_usage")&.dig('value') || 0
        }
      },
      billing_history: extract_billing_history(@subscription),
      status_changes: extract_status_changes(@subscription)
    }
    
    # Calculate average monthly usage for key metrics
    %w[api_requests storage_usage bandwidth_usage].each do |metric|
      analytics_data[:average_monthly_usage][metric] = @subscription.average_monthly_usage(metric)
    end
    
    render_success(analytics_data)
  end
  
  private
  
  def set_subscription
    @subscription = current_account.app_subscriptions.find_by(id: params[:id])
    render_error('Subscription not found', status: :not_found) unless @subscription
  end
  
  def set_app
    @app = App.find_by(id: params[:app_id])
    render_error('App not found', status: :not_found) unless @app
  end
  
  def authorize_subscription_access
    return true if @subscription.account == current_account
    return true if current_user.has_permission?('subscriptions.manage')
    
    render_error('Unauthorized to access this subscription', status: :forbidden)
    false
  end
  
  def subscription_params
    params.require(:app_subscription).permit(
      :app_plan_id,
      configuration: {}
    )
  end
  
  def subscription_update_params
    params.require(:app_subscription).permit(
      configuration: {}
    )
  end
  
  def subscription_data(subscription, detailed: false)
    data = {
      id: subscription.id,
      status: subscription.status,
      subscribed_at: subscription.subscribed_at,
      next_billing_at: subscription.next_billing_at,
      cancelled_at: subscription.cancelled_at,
      created_at: subscription.created_at,
      updated_at: subscription.updated_at,
      app: {
        id: subscription.app.id,
        name: subscription.app.name,
        slug: subscription.app.slug,
        status: subscription.app.status,
        icon_url: subscription.app.icon_url
      },
      app_plan: {
        id: subscription.app_plan.id,
        name: subscription.app_plan.name,
        slug: subscription.app_plan.slug,
        price_cents: subscription.app_plan.price_cents,
        billing_interval: subscription.app_plan.billing_interval,
        formatted_price: subscription.app_plan.formatted_price
      }
    }
    
    if detailed
      data.merge!(
        configuration: subscription.configuration,
        usage_metrics: subscription.usage_metrics,
        enabled_features: subscription.enabled_features.map { |feature|
          {
            slug: feature.slug,
            name: feature.name,
            description: feature.description
          }
        },
        limits: subscription.app_plan.limits,
        permissions: subscription.app_plan.permissions,
        usage_within_limits: subscription.usage_within_limits?,
        next_billing_amount: subscription.formatted_next_billing_amount,
        days_until_billing: subscription.days_until_billing,
        subscription_age_days: subscription.subscription_age_in_days,
        total_amount_paid: subscription.total_amount_paid
      )
    end
    
    data
  end
  
  def extract_billing_history(subscription)
    billing_metrics = subscription.usage_metrics.select { |k, v| k.include?('billing_processed') }
    billing_metrics.map do |key, data|
      {
        date: data['recorded_at'],
        amount: data['value'],
        formatted_amount: "$#{data['value'] / 100.0}"
      }
    end.sort_by { |item| item[:date] }.reverse
  end
  
  def extract_status_changes(subscription)
    status_metrics = subscription.usage_metrics.select { |k, v|
      %w[paused resumed cancelled expired].any? { |status| k.include?(status) }
    }
    status_metrics.map do |key, data|
      {
        status: key.split('_').first,
        date: data['recorded_at'],
        reason: data.dig('metadata', 'reason')
      }
    end.sort_by { |item| item[:date] }.reverse
  end
end