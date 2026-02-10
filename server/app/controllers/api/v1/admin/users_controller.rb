# frozen_string_literal: true

class Api::V1::Admin::UsersController < ApplicationController
  before_action -> { require_permission("admin.user.read") }, only: [ :index, :show ]
  before_action -> { require_permission("admin.user.create") }, only: [ :create ]
  before_action -> { require_permission("admin.user.update") }, only: [ :update ]
  before_action -> { require_permission("admin.user.delete") }, only: [ :destroy ]
  before_action -> { require_permission("admin.user.impersonate") }, only: [ :impersonate ]
  before_action :find_user, only: [ :show, :update, :destroy, :impersonate ]
  before_action :find_account, only: [ :create ]

  # GET /api/v1/admin/users
  def index
    # For system admin, return ALL users across ALL accounts
    @users = User.includes(:account).order(:created_at)
    render_success(
      data: @users.map { |user| user_summary(user) }
    )
  end

  # GET /api/v1/admin/users/:id
  def show
    render_success(
      data: user_summary(@user)
    )
  end

  # POST /api/v1/admin/users
  def create
    @user = @account.users.build(user_params)

    # Default role will be assigned by User model callback

    # Generate temporary password
    temp_password = SecureRandom.alphanumeric(12)
    @user.password = temp_password
    @user.password_confirmation = temp_password

    if @user.save
      # Send welcome email with login instructions via worker service
      WorkerJobService.enqueue_welcome_email(@user.id, temp_password)

      AuditLog.create!(
        account: @account,
        user: current_user,
        action: "create",
        resource_type: "User",
        resource_id: @user.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        metadata: {
          user_email: @user.email,
          account_name: @account.name,
          details: "Created user #{@user.email} in account #{@account.name}"
        }
      )

      render_success(
        data: user_summary(@user),
        message: "User created successfully",
        status: :created
      )
    else
      render_validation_error(@user)
    end
  end

  # PATCH/PUT /api/v1/admin/users/:id
  def update
    update_params = user_params
    roles_to_assign = update_params.delete(:roles) # Remove roles from params for separate handling

    Rails.logger.info "Update params after role removal: #{update_params.inspect}"
    Rails.logger.info "Roles to assign: #{roles_to_assign.inspect}"

    # Update basic user attributes first
    if @user.update(update_params)
      Rails.logger.info "User update successful"

      # Handle role assignments if provided
      if roles_to_assign.present?
        begin
          Rails.logger.info "Attempting to assign roles: #{roles_to_assign.inspect}"
          # Validate roles exist
          valid_roles = Role.where(name: roles_to_assign)
          Rails.logger.info "Found valid roles: #{valid_roles.pluck(:name, :id).inspect}"

          # Validate user has permission to assign these roles
          unauthorized_roles = valid_roles.reject { |role| can_assign_role?(role) }
          if unauthorized_roles.any?
            return render_error(
              "You do not have permission to assign the following roles: #{unauthorized_roles.pluck(:name).join(', ')}",
              :forbidden
            )
          end

          if valid_roles.count != roles_to_assign.count
            invalid_roles = roles_to_assign - valid_roles.pluck(:name)
            return render_error(
              "Invalid roles: #{invalid_roles.join(', ')}",
              :unprocessable_content
            )
          end

          # Check if user is trying to modify their own system admin role
          current_user_roles = @user.roles.pluck(:name)
          if @user.id == current_user.id &&
             current_user_roles.include?("system.admin") &&
             !roles_to_assign.include?("system.admin")
            return render_error(
              "You cannot remove your own system admin role",
              :forbidden
            )
          end

          # Update user roles - handle existing roles properly
          current_role_ids = @user.roles.pluck(:id)
          new_role_ids = valid_roles.pluck(:id)

          # Remove roles that are no longer assigned
          roles_to_remove = current_role_ids - new_role_ids
          @user.user_roles.where(role_id: roles_to_remove).destroy_all if roles_to_remove.any?

          # Add new roles that aren't already assigned
          roles_to_add = new_role_ids - current_role_ids
          if roles_to_add.any?
            Rails.logger.info "Adding roles with IDs: #{roles_to_add.inspect}"
            roles_to_add.each do |role_id|
              Rails.logger.info "Creating user_role for role_id: #{role_id}"
              user_role = @user.user_roles.create(role_id: role_id, granted_by_id: current_user.id, granted_at: Time.current)
              unless user_role.persisted?
                Rails.logger.error "Failed to create user_role for role #{role_id}: #{user_role.errors.full_messages.join(', ')}"
                raise "Failed to create user role: #{user_role.errors.full_messages.join(', ')}"
              end
            end
          end

          audit_log = AuditLog.create(
            account: @user.account,
            user: current_user,
            action: "role_change",
            resource_type: "User",
            resource_id: @user.id,
            source: "admin_panel",
            ip_address: request.remote_ip,
            metadata: {
              updated_roles: roles_to_assign,
              user_email: @user.email,
              details: "Updated roles for user #{@user.email} to: #{roles_to_assign.join(', ')}"
            }
          )

          unless audit_log.persisted?
            Rails.logger.error "Failed to create audit log: #{audit_log.errors.full_messages.join(', ')}"
          end
        rescue StandardError => e
          return render_error(
            "Failed to update roles: #{e.message}",
            :unprocessable_content
          )
        end
      end

      # Log general user update
      begin
        general_audit_log = AuditLog.create(
          account: @user.account,
          user: current_user,
          action: "update",
          resource_type: "User",
          resource_id: @user.id,
          source: "admin_panel",
          ip_address: request.remote_ip,
          metadata: {
            user_email: @user.email,
            details: "Updated user #{@user.email}"
          }
        )

        unless general_audit_log.persisted?
          Rails.logger.error "Failed to create general user audit log: #{general_audit_log.errors.full_messages.join(', ')}"
        end
      rescue StandardError => e
        Rails.logger.error "Failed to create audit log: #{e.message}"
        # Don't fail the request if audit logging fails
      end

      Rails.logger.info "User role update completed successfully"

      begin
        Rails.logger.info "Generating user summary data"
        user_data = user_summary(@user)
        Rails.logger.info "User summary generated successfully"
        render_success(
          data: user_data,
          message: "User updated successfully"
        )
      rescue StandardError => e
        Rails.logger.error "Failed to generate user summary: #{e.message}"
        render_success(
          data: { id: @user.id, email: @user.email },
          message: "User updated successfully (summary generation failed)"
        )
      end
    else
      Rails.logger.error "User update failed: #{@user.errors.full_messages.join(', ')}"
      render_validation_error(@user)
    end
  end

  # DELETE /api/v1/admin/users/:id
  def destroy
    # Prevent self-deletion
    if @user.id == current_user.id
      return render_error(
        "You cannot delete your own account",
        :forbidden
      )
    end

    # Prevent deletion of account owners unless there's another owner
    if @user.owner?
      other_owners = @user.account.users.with_role("owner").where.not(id: @user.id)
      if other_owners.empty?
        return render_error(
          "Cannot delete the only account owner. Transfer ownership first.",
          :forbidden
        )
      end
    end

    account = @user.account
    user_email = @user.email

    if @user.destroy
      AuditLog.create!(
        account: account,
        user: current_user,
        action: "delete",
        resource_type: "User",
        resource_id: @user.id,
        source: "admin_panel",
        ip_address: request.remote_ip,
        metadata: {
          user_email: user_email,
          details: "Deleted user #{user_email}"
        }
      )

      render_success(
        message: "User deleted successfully"
      )
    else
      render_validation_error(@user)
    end
  end

  # POST /api/v1/admin/users/:id/impersonate
  def impersonate
    unless defined?(PowernodeEnterprise::Engine)
      return render_error("Impersonation requires enterprise edition", :forbidden)
    end

    service = Auth::ImpersonationService.new(current_user)

    begin
      token = service.start_impersonation(
        target_user_id: @user.id,
        reason: params[:reason],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      render_success(
        data: {
          token: token,
          target_user: user_summary(@user),
          expires_at: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).iso8601
        },
        message: "Impersonation started successfully",
        status: :created
      )
    rescue Auth::ImpersonationService::Error => e
      render_error(
        e.message,
        e.http_status,
        details: { code: e.error_code }
      )
    rescue StandardError => e
      Rails.logger.error "Impersonation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render_error(
        "Failed to start impersonation",
        :internal_server_error,
        details: { code: "impersonation_failed" }
      )
    end
  end

  private

  def find_user
    # For admin operations, find user across all accounts
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  end

  def find_account
    account_id = params[:account_id]
    return render_error("Account ID required", status: :bad_request) unless account_id

    @account = Account.find(account_id)
  rescue ActiveRecord::RecordNotFound => e
    render_error(e.message, status: :not_found)
  end

  def user_params
    params.require(:user).permit(
      :email, :name, :phone, :timezone, :status,
      roles: []
    )
  end



  def user_summary(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      full_name: user.full_name,
      roles: user.role_names,  # Use multi-role system
      permissions: user.permissions.pluck(:name),
      status: user.status,
      email_verified: user.email_verified?,
      locked: user.locked?,
      failed_login_attempts: user.failed_login_attempts,
      last_login_at: user.last_login_at&.iso8601,
      created_at: user.created_at.iso8601,
      updated_at: user.updated_at.iso8601,
      preferences: user.preferences || {},
      account: {
        id: user.account.id,
        name: user.account.name,
        status: user.account.status
      }
    }
  end

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
end
