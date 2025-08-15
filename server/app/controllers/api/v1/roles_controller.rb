# frozen_string_literal: true

class Api::V1::RolesController < ApplicationController
  before_action :require_permission, only: [ :index, :show, :create, :update, :destroy ]

  # GET /api/v1/roles
  def index
    roles = Role.includes(:permissions).order(:name)

    render json: {
      success: true,
      data: roles.map { |role| role_data(role) }
    }, status: :ok
  end

  # GET /api/v1/roles/:id
  def show
    role = Role.find(params[:id])

    render json: {
      success: true,
      data: role_data(role)
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Role not found"
    }, status: :not_found
  end

  # POST /api/v1/roles
  def create
    role = Role.new(role_params)

    if role.save
      render json: {
        success: true,
        data: role_data(role),
        message: "Role created successfully"
      }, status: :created
    else
      render json: {
        success: false,
        error: "Role creation failed",
        details: role.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/roles/:id
  def update
    role = Role.find(params[:id])

    if role.update(role_params)
      render json: {
        success: true,
        data: role_data(role),
        message: "Role updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Role update failed",
        details: role.errors.full_messages
      }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Role not found"
    }, status: :not_found
  end

  # DELETE /api/v1/roles/:id
  def destroy
    role = Role.find(params[:id])

    # Prevent deletion of system roles
    if [ "Owner", "Admin", "Member" ].include?(role.name)
      return render json: {
        success: false,
        error: "Cannot delete system roles"
      }, status: :unprocessable_content
    end

    if role.destroy
      render json: {
        success: true,
        message: "Role deleted successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Role deletion failed",
        details: role.errors.full_messages
      }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Role not found"
    }, status: :not_found
  end

  private

  def require_permission
    require_permission("roles.read")  # Minimum permission needed
  end

  def role_params
    params.require(:role).permit(:name, :description, permission_ids: [])
  end

  def role_data(role)
    {
      id: role.id,
      name: role.name,
      description: role.description,
      created_at: role.created_at,
      updated_at: role.updated_at,
      permissions: role.permissions.map { |permission|
        {
          id: permission.id,
          name: permission.name,
          description: permission.description
        }
      },
      users_count: role.users.count
    }
  end
end
