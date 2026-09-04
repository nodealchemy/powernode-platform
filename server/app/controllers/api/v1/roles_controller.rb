# frozen_string_literal: true

class Api::V1::RolesController < ApplicationController
  include RoleAssignmentGuard

  before_action -> { require_permission("admin.role.read") }, only: [ :index, :show, :users ]
  before_action -> { require_permission("admin.role.create") }, only: [ :create ]
  before_action -> { require_permission("admin.role.update") }, only: [ :update ]
  before_action -> { require_permission("admin.role.delete") }, only: [ :destroy ]
  before_action -> { require_permission("admin.role.assign") }, only: [ :assign_to_user, :remove_from_user ]
  before_action :find_role, only: [ :show, :update, :destroy, :users ]
  before_action :find_user, only: [ :assign_to_user, :remove_from_user ]

  # GET /api/v1/roles — global (code-defined) roles + this account's custom roles
  def index
    # Eager-load grants so permission display doesn't query per role, and compute
    # every role's user count in ONE grouped query instead of `role.users.count`
    # per row (the two per-role N+1 sources in role_data).
    roles = visible_roles.includes(:role_permissions).order(:account_id, :name).to_a
    user_counts = UserRole.where(role_id: roles.map(&:id)).group(:role_id).count

    render_success(roles.map do |role|
      role_data(
        role,
        users_count: user_counts[role.id] || 0,
        permission_names: role.role_permissions.map(&:permission_name)
      )
    end)
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

  # POST /api/v1/roles — creates an ACCOUNT-SCOPED custom role (global roles are code-defined)
  def create
    @role = Role.new(role_params)
    @role.account_id = current_user.account_id # custom roles belong to the acting account
    @role.role_type = "user"
    @role.is_system = false

    unless @role.save
      return render_validation_error(@role)
    end

    if params[:permission_names].present?
      ok, error = apply_permission_names(@role, params[:permission_names])
      unless ok
        @role.destroy
        return render_error(error, status: :forbidden)
      end
    end

    render_success(role_data(@role.reload), status: :created)
  end

  # PATCH/PUT /api/v1/roles/:id — only account-scoped custom roles are editable
  def update
    return render_error("Global roles are code-defined and read-only", status: :forbidden) if @role.account_id.nil?

    unless @role.update(role_params)
      return render_validation_error(@role)
    end

    if params.key?(:permission_names)
      ok, error = apply_permission_names(@role, params[:permission_names])
      return render_error(error, status: :forbidden) unless ok
    end

    render_success(role_data(@role.reload))
  end

  # DELETE /api/v1/roles/:id — only account-scoped custom roles can be deleted
  def destroy
    return render_error("Global roles are code-defined and cannot be deleted", status: :forbidden) if @role.account_id.nil?

    if @role.users.any?
      return render_error("Cannot delete role that is assigned to users", status: :conflict)
    end

    if @role.destroy
      render_success(nil)
    else
      render_validation_error(@role)
    end
  end

  # GET /api/v1/roles/assignable — roles the current user may assign
  def assignable
    assignable_roles = visible_roles.where.not(role_type: "system")

    # Every actor is filtered by the subset test — there is no admin exemption
    # (IMP-1635cb7fa768). This MIRRORS Role#assignable_by? and must keep
    # mirroring it: a picker that offers more than #assign_to_user will accept
    # hands the operator a role the write path then refuses. The only remaining
    # short-circuit is the one #assignable_by? has, `system.admin` (which holds
    # everything by definition, and whose #permission_names is the running
    # process's catalog rather than its true set); the system-role refusal is
    # moot here because the query above already excluded them.
    unless current_user.has_permission?("system.admin")
      user_permissions = current_user.permission_names
      assignable_roles = assignable_roles.select do |role|
        role_permissions_subset_of_user?(role, user_permissions)
      end
    end

    render_success(assignable_roles.map { |role| assignable_role_data(role) })
  end

  # POST /api/v1/roles/:id/assign_to_user/:user_id
  def assign_to_user
    role = visible_roles.find(params[:id])

    unless can_assign_role?(role)
      return render_error("You do not have permission to assign this role", status: :forbidden)
    end

    @user.assign_role(role, assigned_by: current_user)
    render_success(user_with_roles(@user))
  rescue ActiveRecord::RecordNotFound
    render_error("Role not found", status: :not_found)
  rescue StandardError => e
    render_error("Failed to assign role: #{e.message}", status: :unprocessable_content)
  end

  # DELETE /api/v1/roles/:id/remove_from_user/:user_id
  def remove_from_user
    role = visible_roles.find(params[:id])

    # NOT @user.remove_role(role): that method takes a role NAME and resolves
    # it via Role.find_by(name:), which is only unique per account_id — passing
    # this already-scoped Role object silently fails to match (find_by(name:)
    # on an object), and even passing role.name could hit the WRONG account's
    # same-named role. `role` here is already the correct, visible_roles-scoped
    # record, so remove it from the association directly.
    @user.roles.delete(role)
    render_success(user_with_roles(@user))
  rescue ActiveRecord::RecordNotFound
    render_error("Role not found", status: :not_found)
  rescue StandardError => e
    render_error("Failed to remove role: #{e.message}", status: :unprocessable_content)
  end

  private

  # Global roles (account_id nil) + the acting account's custom roles. This is
  # the isolation boundary — a user never sees another account's custom roles.
  def visible_roles
    Role.for_account(current_user.account_id)
  end

  def find_role
    @role = visible_roles.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Role not found", status: :not_found)
  end

  def find_user
    # Scope to the acting account's users: a foreign user_id must 404, never
    # allow cross-tenant role grant/revoke (User belongs_to :account).
    @user = current_user.account.users.find(params[:user_id])
  rescue ActiveRecord::RecordNotFound
    render_error("User not found", status: :not_found)
  end

  def role_params
    params.require(:role).permit(:name, :display_name, :description)
  end

  # Reconcile a custom role's grants to `names`, enforcing the escalation guard:
  # every name must be a catalog permission the current user is allowed to grant
  # (held by them, never system-tier). Returns [ok, error_message].
  def apply_permission_names(role, names)
    names = Array(names).map(&:to_s).uniq

    unknown = names.reject { |n| Permissions.permission_exists?(n) }
    return [ false, "Unknown permissions: #{unknown.join(', ')}" ] if unknown.any?

    ungrantable = names.reject { |n| current_user.can_grant_permission?(n) }
    if ungrantable.any?
      return [ false, "You cannot grant permissions you do not hold (or system-tier permissions): #{ungrantable.join(', ')}" ]
    end

    current = role.role_permissions.pluck(:permission_name)
    (current - names).each { |n| role.remove_permission(n) }
    (names - current).each { |n| role.add_permission(n) }
    [ true, nil ]
  end

  # `users_count` / `permission_names` may be supplied by the index (computed in
  # bulk to avoid an N+1); single-record callers omit them and fall back to a
  # per-record query.
  def role_data(role, users_count: nil, permission_names: nil)
    permission_names ||= role.role_permissions.pluck(:permission_name)
    users_count = role.users.count if users_count.nil?

    {
      id: role.id,
      name: role.name,
      display_name: role.display_name,
      description: role.description,
      account_id: role.account_id,
      scope: role.account_id ? "account" : "global",
      editable: role.account_id.present? && role.account_id == current_user.account_id,
      system_role: role.system_role?,
      role_type: role.role_type,
      # Literal grants (not the system.admin-expanded set) for display
      permissions: permission_names.sort.map { |name| permission_brief(name) },
      users_count: users_count,
      created_at: role.created_at,
      updated_at: role.updated_at
    }
  end

  # Builds permission display data from a catalog name (no Permission row exists).
  def permission_brief(name)
    parts = name.split(".")
    {
      id: name,
      name: name,
      resource: parts[0..-2].join("."),
      action: parts.last,
      description: Permissions.permission_description(name)
    }
  end

  def user_with_roles(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      full_name: user.full_name,
      status: user.status,
      account: user.account ? { id: user.account.id, name: user.account.name } : nil,
      roles: user.role_names || [],
      permissions: user.permission_names || [],
      created_at: user.created_at,
      last_login_at: user.last_login_at
    }
  end

  # Simplified role data for assignment pickers
  def assignable_role_data(role)
    {
      id: role.id,
      name: role.name,
      value: role.name,
      label: role.name.split(".").map(&:titleize).join(" "),
      description: role.description,
      scope: role.account_id ? "account" : "global",
      system_role: role.system_role?,
      role_type: role.role_type,
      permission_count: role.role_permissions.count,
      users_count: role.users.count
    }
  end
end
