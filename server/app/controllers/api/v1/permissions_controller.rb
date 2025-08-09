# frozen_string_literal: true

class Api::V1::PermissionsController < ApplicationController
  before_action :require_permission

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

  def require_permission
    require_permission("roles.read")  # Need roles permission to view permissions
  end

  def permission_data(permission)
    {
      id: permission.id,
      name: permission.name,
      description: permission.description,
      created_at: permission.created_at,
      updated_at: permission.updated_at,
      roles_count: permission.roles.count
    }
  end
end
