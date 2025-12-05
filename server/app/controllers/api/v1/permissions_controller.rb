# frozen_string_literal: true

class Api::V1::PermissionsController < ApplicationController
  before_action :require_admin_permission

  # GET /api/v1/permissions
  def index
    permissions = Permission.order(:name)

    render_success(
      data: permissions.map { |permission| permission_data(permission) }
    )
  end

  # GET /api/v1/permissions/:id
  def show
    permission = Permission.find(params[:id])

    render_success(
      data: permission_data(permission)
    )
  rescue ActiveRecord::RecordNotFound
    render_error("Permission not found", status: :not_found)
  end

  private

  def require_admin_permission
    # Allow users with admin.role.view or admin.access permissions to view permissions
    user_permissions = current_user&.permission_names || []

    unless user_permissions.include?('admin.role.view') ||
           user_permissions.include?('admin.access') ||
           user_permissions.include?('system.admin')
      render_error("Unauthorized access to permissions", status: :forbidden)
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
