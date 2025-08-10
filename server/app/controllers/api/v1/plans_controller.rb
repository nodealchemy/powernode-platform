# frozen_string_literal: true

class Api::V1::PlansController < ApplicationController
  before_action :authenticate_request, except: [:public_index]
  before_action :require_admin_access, except: [:index, :show, :public_index]
  before_action :set_plan, only: [:show, :update, :destroy]

  # GET /api/v1/public/plans (public endpoint for registration)
  def public_index
    @plans = Plan.active.public_plans.order(:price_cents)

    render json: {
      success: true,
      data: {
        plans: @plans.map { |plan| public_plan_data(plan) },
        total_count: @plans.count
      }
    }, status: :ok
  end

  # GET /api/v1/plans
  def index
    @plans = if current_user.admin? || current_user.owner?
               # Admins can see all plans
               Plan.includes(:subscriptions).order(:created_at)
             else
               # Regular users only see public, active plans
               Plan.active.public_plans.order(:price_cents)
             end

    render json: {
      success: true,
      data: {
        plans: @plans.map { |plan| plan_data(plan) },
        total_count: @plans.count
      }
    }, status: :ok
  end

  # GET /api/v1/plans/:id
  def show
    render json: {
      success: true,
      data: {
        plan: detailed_plan_data(@plan)
      }
    }, status: :ok
  end

  # POST /api/v1/plans
  def create
    @plan = Plan.new(plan_params)

    if @plan.save
      # Log plan creation
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'create_plan',
        resource_type: 'Plan',
        resource_id: @plan.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          plan_name: @plan.name,
          price_cents: @plan.price_cents,
          billing_cycle: @plan.billing_cycle
        }
      )

      render json: {
        success: true,
        data: {
          plan: detailed_plan_data(@plan),
          message: "Plan created successfully"
        }
      }, status: :created
    else
      render json: {
        success: false,
        error: "Failed to create plan",
        details: @plan.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PUT /api/v1/plans/:id
  def update
    old_values = @plan.attributes.slice('name', 'price_cents', 'billing_cycle', 'status')
    
    if @plan.update(plan_params)
      # Log plan update
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'update_plan',
        resource_type: 'Plan',
        resource_id: @plan.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        old_values: old_values,
        new_values: @plan.attributes.slice('name', 'price_cents', 'billing_cycle', 'status'),
        metadata: {
          plan_name: @plan.name,
          changes: @plan.previous_changes.keys
        }
      )

      render json: {
        success: true,
        data: {
          plan: detailed_plan_data(@plan),
          message: "Plan updated successfully"
        }
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Failed to update plan",
        details: @plan.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/plans/:id
  def destroy
    unless @plan.can_be_deleted?
      return render json: {
        success: false,
        error: "Cannot delete plan with active subscriptions"
      }, status: :unprocessable_content
    end

    # Log plan deletion before destroying
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: 'delete_plan',
      resource_type: 'Plan',
      resource_id: @plan.id,
      source: 'admin_panel',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      old_values: @plan.attributes,
      metadata: {
        plan_name: @plan.name,
        subscription_count: @plan.subscriptions.count
      }
    )

    if @plan.destroy
      render json: {
        success: true,
        message: "Plan deleted successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Failed to delete plan",
        details: @plan.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # POST /api/v1/plans/:id/duplicate
  def duplicate
    set_plan
    
    new_plan = @plan.dup
    new_plan.name = "#{@plan.name} (Copy)"
    new_plan.status = 'inactive'
    new_plan.stripe_price_id = nil
    new_plan.paypal_plan_id = nil

    if new_plan.save
      render json: {
        success: true,
        data: {
          plan: detailed_plan_data(new_plan),
          message: "Plan duplicated successfully"
        }
      }, status: :created
    else
      render json: {
        success: false,
        error: "Failed to duplicate plan",
        details: new_plan.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PUT /api/v1/plans/:id/toggle_status
  def toggle_status
    set_plan
    
    new_status = @plan.status == 'active' ? 'inactive' : 'active'
    
    if @plan.update(status: new_status)
      # Log status change
      AuditLog.create!(
        user: current_user,
        account: current_user.account,
        action: 'toggle_plan_status',
        resource_type: 'Plan',
        resource_id: @plan.id,
        source: 'admin_panel',
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          plan_name: @plan.name,
          old_status: @plan.status_was,
          new_status: new_status
        }
      )

      render json: {
        success: true,
        data: {
          plan: detailed_plan_data(@plan),
          message: "Plan status updated successfully"
        }
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Failed to update plan status",
        details: @plan.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  private

  def set_plan
    @plan = Plan.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Plan not found"
    }, status: :not_found
  end

  def require_admin_access
    unless current_user.admin? || current_user.owner?
      render json: {
        success: false,
        error: "Access denied: Admin privileges required"
      }, status: :forbidden
    end
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
      :stripe_price_id,
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
      metadata: {},
      volume_discount_tiers: []
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
      active_subscription_count: plan.subscriptions.where(status: ['active', 'trialing']).count,
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
      metadata: plan.metadata || {},
      stripe_price_id: plan.stripe_price_id,
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
      created_at: plan.created_at,
      updated_at: plan.updated_at
    }
  end
end