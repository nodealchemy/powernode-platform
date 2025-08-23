# frozen_string_literal: true

class Api::V1::PermissionsController < ApplicationController
  before_action :require_admin_permission

  # GET /api/v1/permissions
  def index
    permissions = Permission.order(:name)

    render json: {
      success: true,
      data: permissions.map { |permission| permission_data(permission) }
    }, status: :ok
  end

  # GET /api/v1/permissions/:id
  def show
    permission = Permission.find(params[:id])

    render json: {
      success: true,
      data: permission_data(permission)
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Permission not found"
    }, status: :not_found
  end

  private

  def require_admin_permission
    # Allow users with admin.role.view or admin.access permissions to view permissions
    user_permissions = current_user&.permission_names || []
    
    unless user_permissions.include?('admin.role.view') || 
           user_permissions.include?('admin.access') ||
           user_permissions.include?('system.admin')
      render json: {
        success: false,
        error: "Unauthorized access to permissions"
      }, status: :forbidden
    end
  end

  def permission_data(permission)
    {
      id: permission.id,
      name: permission.name,
      resource: permission.resource,
      action: permission.action,
      description: permission.description,
      created_at: permission.created_at,
      updated_at: permission.updated_at,
      roles_count: permission.role_permissions.count
    }
  end
end
