# frozen_string_literal: true

class Api::V1::AppPlansController < ApplicationController
  include AuditLogging

  # Authentication is handled by ApplicationController's before_action :authenticate_request
  before_action :set_app
  before_action :authorize_app_access
  before_action :set_plan, only: [ :show, :update, :destroy, :activate, :deactivate ]

  def index
    plans = @app.app_plans.includes(:app)

    # Apply filters
    plans = plans.active if params[:active] == "true"
    plans = plans.inactive if params[:active] == "false"
    plans = plans.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

    # Apply sorting
    case params[:sort]
    when "name"
      plans = plans.order(:name)
    when "price"
      plans = plans.order(:price_cents)
    when "created_at"
      plans = plans.order(created_at: :desc)
    else
      plans = plans.order(:sort_order, :name)
    end

    render_success(
      data: plans.map { |plan| plan_data(plan) }
    )
  end

  def show
    render_success(
      data: plan_data(@plan, detailed: true)
    )
  end

  def create
    @plan = @app.app_plans.build(plan_params)
    @plan.sort_order = @app.app_plans.maximum(:sort_order).to_i + 1

    if @plan.save
      log_audit_event("app_plan_created", {
        app_id: @app.id,
        plan_id: @plan.id,
        plan_name: @plan.name
      })

      render_success(
        data: plan_data(@plan, detailed: true),
        message: "App plan created successfully",
        status: :created
      )
    else
      render_validation_error(@plan)
    end
  end

  def update
    if @plan.update(plan_params)
      log_audit_event("app_plan_updated", {
        app_id: @app.id,
        plan_id: @plan.id,
        changes: @plan.previous_changes.keys
      })

      render_success(
        data: plan_data(@plan, detailed: true),
        message: "App plan updated successfully"
      )
    else
      render_validation_error(@plan)
    end
  end

  def destroy
    plan_name = @plan.name

    if @plan.destroy
      log_audit_event("app_plan_deleted", {
        app_id: @app.id,
        plan_name: plan_name
      })

      render_success(
        message: "App plan deleted successfully"
      )
    else
      render_validation_error(@plan)
    end
  end

  def activate
    if @plan.activate!
      log_audit_event("app_plan_activated", {
        app_id: @app.id,
        plan_id: @plan.id,
        plan_name: @plan.name
      })

      render_success(
        data: plan_data(@plan, detailed: true),
        message: "App plan activated successfully"
      )
    else
      render_validation_error(@plan)
    end
  end

  def deactivate
    if @plan.deactivate!
      log_audit_event("app_plan_deactivated", {
        app_id: @app.id,
        plan_id: @plan.id,
        plan_name: @plan.name
      })

      render_success(
        data: plan_data(@plan, detailed: true),
        message: "App plan deactivated successfully"
      )
    else
      render_validation_error(@plan)
    end
  end

  def reorder
    plan_ids = params[:plan_ids]

    return render_error("Plan IDs required", status: :bad_request) if plan_ids.blank?

    begin
      ActiveRecord::Base.transaction do
        plan_ids.each_with_index do |plan_id, index|
          plan = @app.app_plans.find(plan_id)
          plan.update!(sort_order: index + 1)
        end
      end

      log_audit_event("app_plans_reordered", {
        app_id: @app.id,
        new_order: plan_ids
      })

      render_success(
        message: "App plans reordered successfully"
      )
    rescue ActiveRecord::RecordNotFound
      render_error("One or more plans not found", status: :not_found)
    rescue StandardError => e
      render_error("Failed to reorder plans", status: :unprocessable_content)
    end
  end

  def compare
    plan_ids = params[:plan_ids]

    return render_error("Plan IDs required for comparison", status: :bad_request) if plan_ids.blank?

    plans = @app.app_plans.where(id: plan_ids).includes(:app)

    return render_error("Plans not found", status: :not_found) if plans.empty?

    comparison_data = plans.map do |plan|
      {
        id: plan.id,
        name: plan.name,
        price_cents: plan.price_cents,
        billing_interval: plan.billing_interval,
        features: plan.features,
        permissions: plan.permissions,
        limits: plan.limits,
        feature_comparison: plan.feature_comparison
      }
    end

    render_success(
      data: {
        plans: comparison_data,
        app: {
          id: @app.id,
          name: @app.name
        }
      }
    )
  end

  def analytics
    analytics_data = {
      total_plans: @app.app_plans.count,
      active_plans: @app.app_plans.active.count,
      inactive_plans: @app.app_plans.inactive.count,
      subscription_distribution: @app.subscription_distribution_by_plan,
      revenue_by_plan: @app.revenue_by_plan,
      most_popular_plan: @app.most_popular_plan&.name,
      average_plan_price: @app.average_plan_price
    }

    render_success(
      data: analytics_data
    )
  end

  private

  def set_app
    @app = current_account.apps.find_by(id: params[:app_id])
    render_error("App not found", status: :not_found) unless @app
  end

  def authorize_app_access
    return true if @app.account == current_account
    return true if current_user.has_permission?("apps.manage")

    render_error("Unauthorized to access this app", status: :forbidden)
    false
  end

  def set_plan
    @plan = @app.app_plans.find_by(id: params[:id])
    render_error("App plan not found", status: :not_found) unless @plan
  end

  def plan_params
    params.require(:app_plan).permit(
      :name, :slug, :description, :price_cents, :billing_interval, :is_active,
      :trial_period_days, :setup_fee_cents, :max_subscribers, :is_featured,
      features: [], permissions: [], limits: {}, metadata: {}
    )
  end

  def plan_data(plan, detailed: false)
    data = {
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      description: plan.description,
      price_cents: plan.price_cents,
      billing_interval: plan.billing_interval,
      is_active: plan.is_active,
      sort_order: plan.sort_order,
      created_at: plan.created_at,
      updated_at: plan.updated_at,
      trial_period_days: plan.trial_period_days,
      setup_fee_cents: plan.setup_fee_cents,
      formatted_price: plan.formatted_price,
      is_free: plan.free?,
      features_count: plan.features.length,
      permissions_count: plan.permissions.length
    }

    if detailed
      data.merge!(
        features: plan.features,
        permissions: plan.permissions,
        limits: plan.limits,
        metadata: plan.metadata,
        max_subscribers: plan.max_subscribers,
        is_featured: plan.is_featured,
        subscription_count: plan.subscription_count,
        active_subscriptions: plan.active_subscriptions_count,
        total_revenue: plan.total_revenue,
        monthly_revenue: plan.monthly_revenue,
        churn_rate: plan.churn_rate,
        upgrade_rate: plan.upgrade_rate,
        downgrade_rate: plan.downgrade_rate,
        feature_comparison: plan.feature_comparison
      )
    end

    data
  end
end
