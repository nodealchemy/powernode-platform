# Admin Services Controller
# Manages service authentication tokens and permissions
class Api::V1::Admin::ServicesController < ApplicationController
  before_action :require_admin!
  before_action :set_service, only: [:show, :update, :destroy, :regenerate_token, :suspend, :activate, :revoke]
  
  # GET /api/v1/admin/services
  def index
    @services = current_account.services
                               .includes(:service_activities)
                               .order(:name)
    
    render json: {
      services: @services.map { |service| service_summary(service) },
      total: @services.size,
      account_services: @services.size
    }
  end
  
  # GET /api/v1/admin/services/:id
  def show
    render json: {
      service: service_details(@service),
      activity_summary: ServiceActivity.activity_summary(@service, 24),
      recent_activities: @service.service_activities
                                 .order(performed_at: :desc)
                                 .limit(50)
                                 .map { |activity| activity_json(activity) }
    }
  end
  
  # POST /api/v1/admin/services
  def create
    @service = Service.create_service!(
      name: service_params[:name],
      description: service_params[:description],
      permissions: service_params[:permissions] || 'standard',
      account: current_account
    )
    
    @service.record_activity!('service_created', {
      created_by_user_id: current_user.id,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      message: "Service '#{@service.name}' created successfully"
    }, status: :created
    
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end
  
  # PATCH/PUT /api/v1/admin/services/:id
  def update
    @service.update!(service_update_params)
    
    @service.record_activity!('service_updated', {
      updated_by_user_id: current_user.id,
      changes: @service.previous_changes,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      message: "Service '#{@service.name}' updated successfully"
    }
    
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end
  
  # DELETE /api/v1/admin/services/:id
  def destroy
    service_name = @service.name
    
    @service.record_activity!('service_deleted', {
      deleted_by_user_id: current_user.id,
      status: 'success'
    })
    
    @service.destroy!
    
    render json: {
      message: "Service '#{service_name}' deleted successfully"
    }
  end
  
  # POST /api/v1/admin/services/:id/regenerate_token
  def regenerate_token
    old_token_preview = @service.masked_token
    new_token = @service.regenerate_token!
    
    @service.record_activity!('token_regenerated', {
      regenerated_by_user_id: current_user.id,
      old_token_preview: old_token_preview,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      new_token: new_token,
      message: "Token regenerated for service '#{@service.name}'"
    }
  end
  
  # POST /api/v1/admin/services/:id/suspend
  def suspend
    @service.suspend!
    
    @service.record_activity!('service_suspended', {
      suspended_by_user_id: current_user.id,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      message: "Service '#{@service.name}' suspended"
    }
  end
  
  # POST /api/v1/admin/services/:id/activate
  def activate
    @service.activate!
    
    @service.record_activity!('service_activated', {
      activated_by_user_id: current_user.id,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      message: "Service '#{@service.name}' activated"
    }
  end
  
  # POST /api/v1/admin/services/:id/revoke
  def revoke
    @service.revoke!
    
    @service.record_activity!('service_revoked', {
      revoked_by_user_id: current_user.id,
      status: 'success'
    })
    
    render json: {
      service: service_details(@service),
      message: "Service '#{@service.name}' revoked"
    }
  end
  
  private
  
  def set_service
    # All users can only access services for their account
    @service = current_account.services.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Service not found' }, status: :not_found
  end
  
  def service_params
    params.require(:service).permit(:name, :description, :permissions)
  end
  
  def service_update_params
    params.require(:service).permit(:name, :description, :permissions)
  end
  
  def ensure_admin_access
    unless current_user.has_permission?('admin') || current_user.has_permission?('super_admin')
      render json: { error: 'Admin access required' }, status: :forbidden
    end
  end
  
  def service_summary(service)
    {
      id: service.id,
      name: service.name,
      description: service.description,
      permissions: service.permissions,
      status: service.status,
      account_name: service.account.name,
      masked_token: service.masked_token,
      request_count: service.request_count || 0,
      last_seen_at: service.last_seen_at&.iso8601,
      active_recently: service.active_in_last_hours(24),
      created_at: service.created_at.iso8601,
      updated_at: service.updated_at.iso8601
    }
  end
  
  def service_details(service)
    service_summary(service).merge({
      token: service.token, # Only show full token in details view
      token_regenerated_at: service.token_regenerated_at&.iso8601
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