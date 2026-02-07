# frozen_string_literal: true

class Api::V1::PlansController < ApplicationController
  before_action :authenticate_request, except: [ :public_index ]
  before_action :require_plan_management_permission, except: [ :index, :show, :public_index, :status ]
  before_action :set_plan, only: [ :show, :update, :destroy ]

  # GET /api/v1/plans/status (dashboard setup check - any authenticated user)
  def status
    total_count = Plan.count
    active_count = Plan.active.count
    public_count = Plan.active.public_plans.count

    render_success({
      has_plans: total_count > 0,
      total_count: total_count,
      active_count: active_count,
      public_count: public_count
    })
  end

  # GET /api/v1/public/plans (public endpoint for registration)
  def public_index
    @plans = Plan.active.public_plans.order(:price_cents)

    render_success({
      plans: @plans.map { |plan| public_plan_data(plan) },
      total_count: @plans.count
    })
  end

  # GET /api/v1/plans
  def index
    @plans = if can?("plans.manage") || can?("admin.billing.view")
               # Users with manage permission can see all plans
               Plan.includes(:subscriptions).order(:created_at)
    else
               # Regular users only see public, active plans
               Plan.active.public_plans.order(:price_cents)
    end

    render_success({
      plans: @plans.map { |plan| plan_data(plan) },
      total_count: @plans.count
    })
  end

  # GET /api/v1/plans/:id
  def show
    render_success({
      plan: detailed_plan_data(@plan)
    })
  end

  # POST /api/v1/plans
  def create
    @plan = Plan.new(plan_params)

    if @plan.save
      # Log plan creation
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "create_plan",
        resource_type: "Plan",
        resource_id: @plan.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          plan_name: @plan.name,
          price_cents: @plan.price_cents,
          billing_cycle: @plan.billing_cycle
        }
      )

      render_success(
        {
          plan: detailed_plan_data(@plan),
          message: "Plan created successfully"
        },
        status: :created
      )
    else
      render_validation_error(@plan)
    end
  end

  # PUT /api/v1/plans/:id
  def update
    old_values = @plan.attributes.slice("name", "price_cents", "billing_cycle", "status")

    if @plan.update(plan_params)
      # Log plan update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "update_plan",
        resource_type: "Plan",
        resource_id: @plan.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        old_values: old_values,
        new_values: @plan.attributes.slice("name", "price_cents", "billing_cycle", "status"),
        metadata: {
          plan_name: @plan.name,
          changes: @plan.previous_changes.keys
        }
      )

      render_success({
        plan: detailed_plan_data(@plan),
        message: "Plan updated successfully"
      })
    else
      render_validation_error(@plan)
    end
  end

  # DELETE /api/v1/plans/:id
  def destroy
    unless @plan.can_be_deleted?
      return render_error(
        "Cannot delete plan with active subscriptions",
        :unprocessable_content
      )
    end

    # Log plan deletion before destroying
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: "delete_plan",
      resource_type: "Plan",
      resource_id: @plan.id,
      source: "admin_panel",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      old_values: @plan.attributes,
      metadata: {
        plan_name: @plan.name,
        subscription_count: @plan.subscriptions.count
      }
    )

    if @plan.destroy
      render_success({
        message: "Plan deleted successfully"
      })
    else
      render_validation_error(@plan)
    end
  rescue ActiveRecord::InvalidForeignKey
    render_error(
      "Cannot delete plan with existing subscriptions",
      :unprocessable_content
    )
  end

  # POST /api/v1/plans/:id/duplicate
  def duplicate
    return unless set_plan

    new_plan = @plan.dup
    new_plan.name = "#{@plan.name} (Copy)"
    new_plan.slug = nil # Will be auto-generated from name
    new_plan.status = "inactive"
    new_plan.paypal_plan_id = nil

    if new_plan.save
      render_success(
        {
          plan: detailed_plan_data(new_plan),
          message: "Plan duplicated successfully"
        },
        status: :created
      )
    else
      render_validation_error(new_plan)
    end
  end

  # PUT /api/v1/plans/:id/toggle_status
  def toggle_status
    return unless set_plan

    old_status = @plan.status
    new_status = old_status == "active" ? "inactive" : "active"

    if @plan.update(status: new_status)
      # Log status change
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: "toggle_plan_status",
        resource_type: "Plan",
        resource_id: @plan.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          plan_name: @plan.name,
          old_status: old_status,
          new_status: new_status
        }
      )

      render_success({
        plan: detailed_plan_data(@plan),
        message: "Plan status updated successfully"
      })
    else
      render_validation_error(@plan)
    end
  end

  private

  def set_plan
    @plan = Plan.find_by(id: params[:id])
    unless @plan
      render_error("Plan not found", status: :not_found)
      return false
    end
    true
  end

  def require_plan_management_permission
    return if current_user.has_permission?("plans.manage") || current_user.has_permission?("admin.billing.view")

    render_error(
      "Permission denied: requires plans.manage or admin.billing.view",
      :forbidden
    )
  end

  def plan_params
    params.require(:plan).permit(
      :name,
      :description,
      :price_cents,
      :currency,
      :billing_cycle,
      :status,
      :trial_days,
      :is_public,
      :paypal_plan_id,
      :has_annual_discount,
      :annual_discount_percent,
      :has_volume_discount,
      :has_promotional_discount,
      :promotional_discount_percent,
      :promotional_discount_start,
      :promotional_discount_end,
      :promotional_discount_code,
      features: {},
      limits: {},
      default_roles: [],
      required_roles: [],
      metadata: {},
      volume_discount_tiers: [ :min_quantity, :discount_percent ]
    )
  end

  def plan_data(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      price_cents: plan.price_cents,
      currency: plan.currency,
      billing_cycle: plan.billing_cycle,
      status: plan.status,
      trial_days: plan.trial_days,
      is_public: plan.is_public,
      formatted_price: plan.price.format,
      monthly_price: plan.monthly_price.format,
      subscription_count: plan.subscriptions.count,
      active_subscription_count: plan.subscriptions.where(status: [ "active", "trialing" ]).count,
      can_be_deleted: plan.can_be_deleted?,
      created_at: plan.created_at,
      updated_at: plan.updated_at
    }
  end

  def detailed_plan_data(plan)
    plan_data(plan).merge(
      features: plan.features,
      limits: plan.limits,
      default_roles: plan.default_roles,
      required_roles: plan.required_roles || [ "account.member" ],
      metadata: plan.metadata || {},
      paypal_plan_id: plan.paypal_plan_id,
      can_be_deleted: plan.can_be_deleted?,
      # Discount fields
      has_annual_discount: plan.has_annual_discount,
      annual_discount_percent: plan.annual_discount_percent,
      has_volume_discount: plan.has_volume_discount,
      volume_discount_tiers: plan.volume_discount_tiers,
      has_promotional_discount: plan.has_promotional_discount,
      promotional_discount_percent: plan.promotional_discount_percent,
      promotional_discount_start: plan.promotional_discount_start&.iso8601,
      promotional_discount_end: plan.promotional_discount_end&.iso8601,
      promotional_discount_code: plan.promotional_discount_code,
      annual_savings_amount: plan.annual_savings_amount.format,
      annual_savings_percentage: plan.annual_savings_percentage
    )
  end

  def public_plan_data(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      price_cents: plan.price_cents,
      currency: plan.currency,
      billing_cycle: plan.billing_cycle,
      trial_days: plan.trial_days,
      formatted_price: plan.price.format,
      monthly_price: plan.monthly_price.format,
      # Include features and limits for plan cards
      features: plan.features || {},
      limits: plan.limits || {},
      # Include discount information for frontend badges
      has_annual_discount: plan.has_annual_discount?,
      annual_discount_percent: plan.annual_discount_percent || 0,
      has_promotional_discount: plan.has_promotional_discount?,
      promotional_discount_percent: plan.promotional_discount_percent || 0,
      promotional_discount_start: plan.promotional_discount_start,
      promotional_discount_end: plan.promotional_discount_end,
      promotional_discount_code: plan.promotional_discount_code,
      has_volume_discount: plan.has_volume_discount?,
      volume_discount_tiers: plan.volume_discount_tiers || [],
      annual_savings_amount: plan.annual_savings_amount.format,
      annual_savings_percentage: plan.annual_savings_percentage,
      created_at: plan.created_at,
      updated_at: plan.updated_at
    }
  end
end
