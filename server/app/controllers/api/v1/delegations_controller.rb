# frozen_string_literal: true

class Api::V1::DelegationsController < ApplicationController
  # Shared privilege-escalation rule for conferring a whole ROLE's authority.
  include RoleAssignmentGuard

  # Authentication is handled by ApplicationController's before_action :authenticate_request
  before_action :set_account
  before_action :set_delegation, only: [ :show, :update, :destroy, :activate, :deactivate, :revoke, :add_permission, :remove_permission ]
  before_action :authorize_delegation_management!, except: [ :show ]
  before_action :authorize_delegation_view!, only: [ :show ]
  before_action :authorize_delegated_role!, only: [ :create, :update ]

  # GET /api/v1/accounts/:account_id/delegations
  def index
    @delegations = @account.account_delegations
                          .includes(:delegated_user, :delegated_by, :role, :revoked_by, :delegation_permissions)
                          .order(:created_at)

    # Filter by status if provided
    @delegations = @delegations.where(status: params[:status]) if params[:status].present?

    # Filter by role if provided
    @delegations = @delegations.where(role_id: params[:role_id]) if params[:role_id].present?

    render_success(
      {
        delegations: @delegations.map { |d| delegation_json(d) },
        meta: {
          total_count: @delegations.count,
          active_count: @delegations.active.count,
          expired_count: @delegations.select(&:expired?).count
        }
      }
    )
  end

  # GET /api/v1/accounts/:account_id/delegations/:id
  def show
    render_success(
      { delegation: delegation_json(@delegation) }
    )
  end

  # POST /api/v1/accounts/:account_id/delegations
  def create
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.create_delegation(
      delegated_user_email: delegation_params[:delegated_user_email],
      role_id: delegation_params[:role_id],
      permission_names: delegation_params[:permission_names],
      expires_at: delegation_params[:expires_at],
      notes: delegation_params[:notes]
    )

    if result[:success]
      render_success(
        { delegation: delegation_json(result[:delegation]), message: "Delegation created successfully" },
        status: :created
      )
    else
      render_error("Failed to create delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # PATCH/PUT /api/v1/accounts/:account_id/delegations/:id
  def update
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.update_delegation(
      delegation: @delegation,
      role_id: delegation_params[:role_id],
      permission_names: delegation_params[:permission_names],
      expires_at: delegation_params[:expires_at],
      notes: delegation_params[:notes]
    )

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Delegation updated successfully" }
      )
    else
      render_error("Failed to update delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # DELETE /api/v1/accounts/:account_id/delegations/:id
  def destroy
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.revoke_delegation(@delegation)

    if result[:success]
      render_success({ message: "Delegation revoked successfully" })
    else
      render_error("Failed to revoke delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/activate
  def activate
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.activate_delegation(@delegation)

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Delegation activated successfully" }
      )
    else
      render_error("Failed to activate delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/deactivate
  def deactivate
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.deactivate_delegation(@delegation)

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Delegation deactivated successfully" }
      )
    else
      render_error("Failed to deactivate delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # PATCH /api/v1/accounts/:account_id/delegations/:id/revoke
  def revoke
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.revoke_delegation(@delegation)

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Delegation revoked successfully" }
      )
    else
      render_error("Failed to revoke delegation", status: :unprocessable_content, details: result[:errors])
    end
  end

  # GET /api/v1/accounts/:account_id/delegations/available_permissions
  def available_permissions
    delegation_service = Accounts::DelegationService.new(current_user, @account)
    role_id = params[:role_id]

    permission_names = delegation_service.list_available_permissions_for_delegation(role_id: role_id)

    render_success(
      {
        permissions: permission_names.map { |name| permission_json(name) },
        role_id: role_id
      }
    )
  end

  # POST /api/v1/accounts/:account_id/delegations/:id/permissions
  def add_permission
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.add_permission_to_delegation(
      delegation: @delegation,
      permission_name: params[:permission_name]
    )

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Permission added successfully" }
      )
    else
      render_error("Failed to add permission", status: :unprocessable_content, details: result[:errors])
    end
  end

  # DELETE /api/v1/accounts/:account_id/delegations/:id/permissions/:permission_name
  def remove_permission
    delegation_service = Accounts::DelegationService.new(current_user, @account)

    result = delegation_service.remove_permission_from_delegation(
      delegation: @delegation,
      permission_name: params[:permission_name]
    )

    if result[:success]
      render_success(
        { delegation: delegation_json(@delegation.reload), message: "Permission removed successfully" }
      )
    else
      render_error("Failed to remove permission", status: :unprocessable_content, details: result[:errors])
    end
  end

  private

  def set_account
    @account = current_user.account

    # Allow admins to manage delegations for other accounts
    if params[:account_id] && current_user.has_permission?("admin.access")
      @account = Account.find(params[:account_id])
    end
  end

  def set_delegation
    @delegation = @account.account_delegations.find(params[:id])
  end

  def authorize_delegation_management!
    unless current_user.has_permission?("accounts.manage") || current_user.has_permission?("admin.access")
      render_error("Insufficient permissions to manage delegations", status: :forbidden)
    end
  end

  # `authorize_delegation_management!` binds WHO may manage delegations. It says
  # nothing about WHAT a delegation may carry — and a delegation IS live
  # authority in the target account, because Authentication#has_permission?
  # resolves a delegated session straight from
  # Account::Delegation#effective_permissions, ahead of any role lookup.
  #
  # A delegation with no custom permissions confers the delegated ROLE's entire
  # permission set, which is the same authority transfer as assigning that role.
  # So it is gated by the same shared rule (RoleAssignmentGuard#can_assign_role?:
  # admins may confer any role, everyone else only a non-system role whose every
  # permission they already hold) rather than by a second, drifting copy of it.
  # The custom-permission-name half of the escalation check lives in
  # Accounts::DelegationService, where the names are validated.
  #
  # Rendering from a before_action halts the chain, so the write never runs.
  def authorize_delegated_role!
    role_id = params.dig(:delegation, :role_id)
    return if role_id.blank?

    role = Role.find_by(id: role_id)
    # An unknown role is the service's error to report, not an escalation.
    return if role.nil?
    return if can_assign_role?(role)

    render_error(
      "You cannot delegate the #{role.name} role: it grants privileges beyond your own",
      status: :forbidden
    )
  end

  def authorize_delegation_view!
    unless current_user.has_permission?("accounts.manage") || current_user.has_permission?("admin.access") || @delegation.delegated_user == current_user
      render_error("Insufficient permissions to view this delegation", status: :forbidden)
    end
  end

  def delegation_params
    params.require(:delegation).permit(:delegated_user_email, :role_id, :expires_at, :notes, permission_names: [])
  end

  def delegation_json(delegation)
    # RESOLVE ONCE PER ROW. Account::Delegation#configured_permissions costs two
    # role queries (Role#has_permission? and Role#permission_names each hit the
    # DB, and neither the role nor the delegation memoizes), so asking for it
    # per field would multiply those across every row of #index.
    configured = delegation.configured_permissions

    {
      id: delegation.id,
      account: {
        id: delegation.account.id,
        name: delegation.account.name,
        subdomain: delegation.account.subdomain
      },
      delegated_user: {
        id: delegation.delegated_user.id,
        email: delegation.delegated_user.email,
        full_name: delegation.delegated_user.full_name
      },
      delegated_by: {
        id: delegation.delegated_by.id,
        email: delegation.delegated_by.email,
        full_name: delegation.delegated_by.full_name
      },
      role: delegation.role ? {
        id: delegation.role.id,
        name: delegation.role.name,
        description: delegation.role.description
      } : nil,
      # THE DISPLAY MUST AGREE WITH THE RESOLVER.
      #
      # `permissions` is the set this delegation is CONFIGURED to confer
      # (Account::Delegation#configured_permissions), NOT the stored
      # delegation_permissions rows. The two diverge once the role changes
      # underneath an existing row: #configured_permissions_for bounds the
      # explicit set by the role LIVE, so a stale stored name stops resolving
      # while the row keeps carrying it. Serializing the raw rows made the API
      # over-report authority — an operator checking whether a delegation is
      # over-scoped read a verb that in fact 403s, and nobody chasing the
      # unexpected 403 found the explanation on the surface meant to explain it.
      #
      # CONFIGURED, NOT EFFECTIVE — and both bases appear in this payload on
      # purpose. `permissions` is status-INDEPENDENT: a revoked, inactive or
      # expired delegation still reports what its configuration resolves to, and
      # a row with no custom permissions therefore reports what its ROLE resolves
      # to for its DELEGATOR — the role's live grants intersected with what
      # `delegated_by` holds, which is what an empty custom set resolves to since
      # IMP-1635cb7fa768 (Account::Delegation#role_backed_permissions). At mint
      # that intersection IS the whole role, so the payload only narrows for a
      # row whose role was widened, or whose delegator was cut back, afterwards.
      # `permissions_summary`
      # below is built from #effective_permissions and is EMPTY unless the
      # delegation is active, so on a non-active row the two disagree by design;
      # `status` and `is_active` in this same payload say which case a reader is
      # in. Pinned by spec/requests/api/v1/delegations_serializer_resolved_permissions_spec.rb.
      #
      # `stale_permission_names` keeps the dropped names VISIBLE rather than
      # silently discarding them: they are what an operator rewrites through
      # PATCH /delegations/:id after a role change. Clearing them one at a time
      # only goes so far — DelegationService refuses the removal that would
      # EMPTY the custom set, since an empty set falls back to the role (bounded
      # by the delegator, but still wider than the pin the removal surrenders).
      permissions: configured.map { |name| permission_json(name) },
      stale_permission_names: delegation.stale_permission_names(configured),
      permission_source: delegation.permission_source,
      permissions_summary: delegation.permissions_summary,
      status: delegation.status,
      expires_at: delegation.expires_at,
      revoked_at: delegation.revoked_at,
      revoked_by: delegation.revoked_by ? {
        id: delegation.revoked_by.id,
        email: delegation.revoked_by.email,
        full_name: delegation.revoked_by.full_name
      } : nil,
      notes: delegation.notes,
      is_active: delegation.active?,
      is_expired: delegation.expired?,
      created_at: delegation.created_at,
      updated_at: delegation.updated_at
    }
  end

  # Permissions are code-defined and identified by NAME. `permission_name` is the
  # canonical identifier; resource/action are derived from the dotted name for
  # display/back-compat.
  def permission_json(permission_name)
    parts = permission_name.to_s.split(".")
    {
      name: permission_name,
      key: permission_name,
      resource: parts[0..-2].join("."),
      action: parts.last,
      description: Permissions.permission_description(permission_name)
    }
  end
end
