# frozen_string_literal: true

# Admin Workers Controller
# Manages worker authentication tokens and permissions
class Api::V1::Admin::WorkersController < ApplicationController
  before_action -> { require_permission('system.workers.read') }, only: [:index, :show]
  before_action -> { require_permission('system.workers.create') }, only: [:create]
  before_action -> { require_permission('system.workers.update') }, only: [:update, :regenerate_token, :suspend, :activate, :revoke]
  before_action -> { require_permission('system.workers.delete') }, only: [:destroy]
  before_action :set_worker, only: [ :show, :update, :destroy, :regenerate_token, :suspend, :activate, :revoke ]

  # GET /api/v1/admin/workers
  def index
    @workers = current_account.workers
                               .includes(:worker_activities)
                               .order(:name)

    render_success(
      workers: @workers.map { |worker| worker_summary(worker) },
      total: @workers.size,
      account_workers: @workers.size
    )
  end

  # GET /api/v1/admin/workers/:id
  def show
    render_success(
      worker: worker_details(@worker),
      activity_summary: WorkerActivity.activity_summary(@worker, 24),
      recent_activities: @worker.worker_activities
                                 .order(performed_at: :desc)
                                 .limit(50)
                                 .map { |activity| activity_json(activity) }
    )
  end

  # POST /api/v1/admin/workers
  def create
    @worker = Worker.create_worker!(
      name: worker_params[:name],
      description: worker_params[:description],
      account: current_account,
      role_names: worker_params[:roles] || ['worker.standard']
    )

    @worker.record_activity!("worker_created", {
      created_by_user_id: current_user.id,
      status: "success"
    })

    render_success(
      { worker: worker_details(@worker), message: "Worker '#{@worker.name}' created successfully" },
      status: :created
    )

  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # PATCH/PUT /api/v1/admin/workers/:id
  def update
    @worker.update!(worker_update_params)

    @worker.record_activity!("worker_updated", {
      updated_by_user_id: current_user.id,
      changes: @worker.previous_changes,
      status: "success"
    })

    render_success(
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' updated successfully"
    )

  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # DELETE /api/v1/admin/workers/:id
  def destroy
    worker_name = @worker.name

    @worker.record_activity!("worker_deleted", {
      deleted_by_user_id: current_user.id,
      status: "success"
    })

    @worker.destroy!

    render_success(message: "Worker '#{worker_name}' deleted successfully")
  end

  # POST /api/v1/admin/workers/:id/regenerate_token
  def regenerate_token
    old_token_preview = @worker.masked_token
    new_token = @worker.regenerate_token!

    @worker.record_activity!("token_regenerated", {
      regenerated_by_user_id: current_user.id,
      old_token_preview: old_token_preview,
      status: "success"
    })

    render_success(
      worker: worker_details(@worker),
      new_token: new_token,
      message: "Token regenerated for worker '#{@worker.name}'"
    )
  end

  # POST /api/v1/admin/workers/:id/suspend
  def suspend
    @worker.suspend!

    @worker.record_activity!("worker_suspended", {
      suspended_by_user_id: current_user.id,
      status: "success"
    })

    render_success(
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' suspended"
    )
  end

  # POST /api/v1/admin/workers/:id/activate
  def activate
    @worker.activate!

    @worker.record_activity!("worker_activated", {
      activated_by_user_id: current_user.id,
      status: "success"
    })

    render_success(
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' activated"
    )
  end

  # POST /api/v1/admin/workers/:id/revoke
  def revoke
    @worker.revoke!

    @worker.record_activity!("worker_revoked", {
      revoked_by_user_id: current_user.id,
      status: "success"
    })

    render_success(
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' revoked"
    )
  end


  private

  def set_worker
    # All users can only access workers for their account
    @worker = current_account.workers.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Worker")
  end

  def worker_params
    params.require(:worker).permit(:name, :description, :permissions, :role)
  end

  def worker_update_params
    params.require(:worker).permit(:name, :description, :permissions)
  end

  def ensure_admin_access
    unless current_user.has_permission?("admin") || current_user.has_permission?("super_admin")
      render_forbidden("Admin access required")
    end
  end

  def worker_summary(worker)
    {
      id: worker.id,
      name: worker.name,
      description: worker.description,
      permissions: worker.permissions,
      status: worker.status,
      role: worker.role,
      account_name: worker.account.name,
      masked_token: worker.masked_token,
      request_count: worker.request_count || 0,
      last_seen_at: worker.last_seen_at&.iso8601,
      active_recently: worker.active_in_last_hours(24),
      created_at: worker.created_at.iso8601,
      updated_at: worker.updated_at.iso8601
    }
  end

  def worker_details(worker)
    worker_summary(worker).merge({
      token: worker.token, # Only show full token in details view
      token_regenerated_at: worker.token_regenerated_at&.iso8601
    })
  end

  def activity_json(activity)
    {
      id: activity.id,
      action: activity.action,
      performed_at: activity.performed_at.iso8601,
      ip_address: activity.ip_address,
      user_agent: activity.user_agent,
      details: activity.details,
      successful: activity.successful?,
      duration: activity.duration
    }
  end
end
