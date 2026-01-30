# frozen_string_literal: true

class Api::V1::RolesController < ApplicationController
  before_action -> { require_permission("admin.role.read") }, only: [ :index, :show, :users ]
  before_action -> { require_permission("admin.role.create") }, only: [ :create ]
  before_action -> { require_permission("admin.role.update") }, only: [ :update ]
  before_action -> { require_permission("admin.role.delete") }, only: [ :destroy ]
  before_action -> { require_permission("admin.role.assign") }, only: [ :assign_to_user, :remove_from_user ]
  before_action :find_role, only: [ :show, :update, :destroy, :users ]
  before_action :find_user, only: [ :assign_to_user, :remove_from_user ]

  # GET /api/v1/roles
  def index
    roles = Role.includes(:permissions).order(:name)

    render_success(roles.map { |role| role_data(role) })
  end

  # GET /api/v1/roles/:id
  def show
    render_success(role_data(@role))
  end

  # GET /api/v1/roles/:id/users
  def users
    users = @role.users.includes(:account, :user_roles).order(:name, :email)

    render_success(users.map { |user| user_with_roles(user) })
  end

  # POST /api/v1/roles
  def create
    # Only allow custom roles to be created (not system roles)
    @role = Role.new(role_params)
    @role.role_type = "user" # Set as user role (non-system role)
    @role.is_system = false

    if @role.save
      # Assign permissions to the role
      if params[:permission_ids].present?
        permissions = Permission.where(id: params[:permission_ids])
        @role.permissions = permissions
      end

      render_success(role_data(@role), status: :created)
    else
      render_validation_error(@role)
    end
  end

  # PATCH/PUT /api/v1/roles/:id
  def update
    # Don't allow updating system roles
    if @role.system_role?
      render_error("System roles cannot be modified", status: :forbidden)
      return
    end

    if @role.update(role_params)
      # Update permissions if provided
      if params[:permission_ids].present?
        permissions = Permission.where(id: params[:permission_ids])
        @role.permissions = permissions
      end

      render_success(role_data(@role))
    else
      render_validation_error(@role)
    end
  end

  # DELETE /api/v1/roles/:id
  def destroy
    # Don't allow deleting system roles
    if @role.system_role?
      render_error("System roles cannot be deleted", status: :forbidden)
      return
    end

    # Check if role is in use
    if @role.users.any?
      render_error("Cannot delete role that is assigned to users", status: :conflict)
      return
    end

    if @role.destroy
      render_success(nil)
    else
      render_validation_error(@role)
    end
  end

  # GET /api/v1/roles/assignable
  # Returns only roles that the current user has permission to assign
  def assignable
    # Start with all non-system roles (role_type != 'system')
    assignable_roles = Role.where.not(role_type: "system").includes(:permissions)

    # System admins and regular admins can assign all roles
    unless current_user.has_permission?("system.admin") || current_user.has_permission?("admin.access")
      # For non-admin users, filter roles based on permissions
      # Users can only assign roles that have permissions they also have
      user_permissions = current_user.permission_names

      assignable_roles = assignable_roles.select do |role|
        role_permissions = role.permissions.pluck(:name)
        # User can assign this role if they have all the permissions that the role grants
        role_permissions.all? { |perm| user_permissions.include?(perm) }
      end
    end

    render_success(assignable_roles.map { |role| assignable_role_data(role) })
  end

  # POST /api/v1/roles/:role_id/assign_to_user/:user_id
  def assign_to_user
    role = Role.find(params[:role_id])

    # Validate that current user can assign this role
    unless can_assign_role?(role)
      render_error("You do not have permission to assign this role", status: :forbidden)
      return
    end

    begin
      @user.assign_role(role, assigned_by: current_user)

      render_success(user_with_roles(@user))
    rescue StandardError => e
      render_error("Failed to assign role: #{e.message}", status: :unprocessable_content)
    end
  end

  # DELETE /api/v1/roles/:role_id/remove_from_user/:user_id
  def remove_from_user
    role = Role.find(params[:role_id])

    begin
      @user.remove_role(role)

      render_success(user_with_roles(@user))
    rescue StandardError => e
      render_error("Failed to remove role: #{e.message}", status: :unprocessable_content)
    end
  end

  private

  def find_role
    @role = Role.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Role not found", status: :not_found)
  end

  def find_user
    @user = User.find(params[:user_id])
  rescue ActiveRecord::RecordNotFound
    render_error("User not found", status: :not_found)
  end

  def role_params
    params.require(:role).permit(:name, :description)
  end

  def role_data(role)
    {
      id: role.id,
      name: role.name,
      description: role.description,
      system_role: role.system_role?,
      permissions: role.permissions.map { |p|
        {
          id: p.id,
          name: "#{p.resource}.#{p.action}",
          resource: p.resource,
          action: p.action,
          description: p.description
        }
      },
      users_count: role.users.count,
      created_at: role.created_at,
      updated_at: role.updated_at
    }
  end

  def user_with_roles(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      full_name: user.full_name,
      status: user.status,
      account: user.account ? {
        id: user.account.id,
        name: user.account.name
      } : nil,
      roles: user.role_names || [],
      permissions: user.permission_names || [],
      created_at: user.created_at,
      last_login_at: user.last_login_at
    }
  end

  private

  # Check if current user can assign a specific role
  def can_assign_role?(role)
    # System admins and regular admins can assign any role
    return true if current_user.has_permission?("system.admin") || current_user.has_permission?("admin.access")

    # System roles cannot be assigned by non-admin users
    return false if role.system_role?

    # Non-admin users can only assign roles that have permissions they also have
    user_permissions = current_user.permission_names
    role_permissions = role.permissions.pluck(:name)

    role_permissions.all? { |perm| user_permissions.include?(perm) }
  end

  # Simplified role data for assignment purposes
  def assignable_role_data(role)
    {
      id: role.id,
      name: role.name,
      value: role.name, # For compatibility with frontend
      label: role.name.split(".").map(&:titleize).join(" "),
      description: role.description,
      system_role: role.system_role?,
      permission_count: role.permissions.count,
      users_count: role.users.count
    }
  end
end
