# frozen_string_literal: true

class Api::V1::AccountsController < ApplicationController
  # Emitted when an account was created but its governance audit row was not
  # written, so the gap is measurable instead of living only in a log line.
  AUDIT_GAP_NOTIFICATION = "audit.write_failed.account_created"

  before_action :set_account, only: [ :show, :update ]
  before_action -> { require_permission("admin.settings.update") }, only: [ :update ]
  # Creating an Account creates a TENANCY BOUNDARY, which is a platform-tier
  # operation, not an account-tier one: `admin.account.create` is deliberately
  # absent from the `owner` role (config/permissions.rb ROLES) so a tenant owner
  # cannot mint sibling tenants. It is held by `admin` and, via `system.admin`,
  # by `super_admin` — which is what a fresh core-mode install's first operator
  # holds (Setup::FirstAdminService grants super_admin explicitly).
  # Defence in depth, ahead of the permission check. `require_permission` resolves
  # against whatever principal authenticated, and a non-user principal (worker /
  # forwarded-mTLS) that ever came to hold this permission would create a tenancy
  # boundary with a NIL actor in the audit row. Worker#has_permission? does not
  # expand system.admin today, so this is unreachable — but a tenancy-boundary
  # write should not depend on a property of a different class to stay closed.
  before_action -> { require_human_operator! }, only: [ :create ]
  before_action -> { require_permission("admin.account.create") }, only: [ :create ]

  # GET /api/v1/accounts/:id
  def show
    render_success(
      data: account_data(@account)
    )
  end

  # POST /api/v1/accounts
  #
  # Creates a new tenant account AND its initial administrator, so what comes
  # back is a usable tenant rather than an empty row nobody can log into. See
  # Accounts::ProvisionService for what "well-formed" means here.
  #
  # Human-operator surface only: this is NOT exposed as an MCP tool. A tenancy
  # boundary write reachable by an agent needs the Ai::AutonomyGate seam, which
  # is a separate decision from building the surface.
  def create
    result = Accounts::ProvisionService.call(
      name: account_create_params[:name],
      subdomain: account_create_params[:subdomain],
      admin_email: account_create_params[:admin_email],
      admin_password: account_create_params[:admin_password],
      admin_name: account_create_params[:admin_name]
    )

    audit_account_created(result)

    render_success(
      status: :created,
      message: "Account created successfully",
      data: account_data(result.account).merge(
        administrator: {
          id: result.administrator.id,
          email: result.administrator.email,
          name: result.administrator.name
        }
      )
    )
  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  rescue ActiveRecord::RecordNotUnique
    # Subdomain uniqueness is checked in Ruby and backstopped by a unique index,
    # so two concurrent provisions of the same subdomain race. The index is what
    # keeps the data correct; this keeps the loser a 409 instead of a 500.
    render_error("Subdomain is already taken", status: :conflict)
  end

  # PATCH/PUT /api/v1/accounts/:id
  def update
    if @account.update(account_params)
      render_success(
        message: "Account updated successfully",
        data: account_data(@account)
      )
    else
      render_validation_error(@account)
    end
  end

  # GET /api/v1/accounts/accessible
  # Returns all accounts accessible to the current user
  def accessible
    service = Auth::AccountSwitchService.new(current_user)
    accounts = service.accessible_accounts

    render_success(
      data: {
        accounts: accounts,
        current_account_id: current_account.id,
        primary_account_id: current_user.account_id
      }
    )
  end

  # POST /api/v1/accounts/switch
  # Switches the current user to a different account context
  def switch
    target_account_id = params[:account_id]

    unless target_account_id.present?
      return render_error("Account ID is required", status: :bad_request)
    end

    service = Auth::AccountSwitchService.new(current_user)

    metadata = {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }

    result = service.switch_to(target_account_id, metadata: metadata)

    render_success(
      message: "Successfully switched to #{result[:account][:name]}",
      data: result
    )
  rescue Auth::AccountSwitchService::UnauthorizedAccountError => e
    render_error(e.message, status: :forbidden)
  rescue Auth::AccountSwitchService::InactiveAccountError,
         Auth::AccountSwitchService::InactiveDelegationError => e
    render_error(e.message, status: :unprocessable_content)
  rescue ActiveRecord::RecordNotFound
    render_error("Account not found", status: :not_found)
  end

  # POST /api/v1/accounts/switch_to_primary
  # Switches the current user back to their primary account
  def switch_to_primary
    service = Auth::AccountSwitchService.new(current_user)

    metadata = {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }

    result = service.switch_to_primary(metadata: metadata)

    render_success(
      message: "Successfully switched back to primary account",
      data: result
    )
  end

  private

  def set_account
    @account = current_account

    # Cross-account reads require the PLATFORM-admin "view all accounts" permission.
    # `accounts.read` is a tenant-level resource permission that every account owner
    # holds, so gating on it let any owner read any other tenant's account by id
    # (cross-tenant IDOR). Workers stay cross-account for report generation;
    # delegated access goes through #switch (which makes the target current_account).
    if !worker_authenticated? && params[:id] != current_account.id && !has_permission?("admin.account.read")
      return render_error("Access denied", status: :forbidden)
    end

    @account = Account.find(params[:id]) if params[:id] != current_account&.id
  rescue ActiveRecord::RecordNotFound
    render_error("Account not found", status: :not_found)
  end

  def account_params
    params.require(:account).permit(:name, :settings, :billing_email, :tax_id)
  end

  # Only an authenticated USER may provision a tenant. Workers and any other
  # non-user principal are refused outright.
  def require_human_operator!
    return if current_user.present?

    render_error("Operator authentication required", status: :forbidden)
  end

  def account_create_params
    params.require(:account).permit(:name, :subdomain, :admin_email, :admin_password, :admin_name)
  end

  # Creating a tenancy boundary is a governance event, so it is written to the
  # audit log against the ACTING operator's account (current_account) rather
  # than the account just created — the operator's trail is where a reviewer
  # looks, and a row filed only under the new tenant is invisible to them.
  # Account's own Auditable callback separately records a "created" row on the
  # new account; this is the actor-attributed half.
  def audit_account_created(result)
    entry = Audit::LoggingService.instance.log(
      action: "account_created",
      resource: result.account,
      user: current_user,
      account: current_account,
      source: "api",
      severity: "high",
      risk_level: "high",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      new_values: {
        "account_id" => result.account.id,
        "name" => result.account.name,
        "subdomain" => result.account.subdomain,
        "administrator_user_id" => result.administrator.id,
        "administrator_email" => result.administrator.email
      }
    )
    return entry if entry

    # Audit::LoggingService swallows its own StandardError outside the test
    # environment and can also drop a write to rate limiting, either of which
    # returns nil. A tenancy boundary created with NO governance record must be
    # countable rather than silent, so the gap is instrumented here. The account
    # is already committed at this point; failing the request would report a
    # failure that did not happen.
    ActiveSupport::Notifications.instrument(
      AUDIT_GAP_NOTIFICATION,
      account_id: result.account.id,
      actor_user_id: current_user&.id
    )
    Rails.logger.error(
      "[accounts#create] account #{result.account.id} was created with NO account_created audit entry"
    )
    nil
  end

  def account_data(account)
    {
      id: account.id,
      name: account.name,
      settings: account.settings,
      billing_email: account.billing_email,
      tax_id: account.tax_id,
      status: account.status,
      created_at: account.created_at,
      updated_at: account.updated_at,
      users_count: account.users.count,
      subscription: (sub = account.current_subscription) ? {
        id: sub.id,
        status: sub.status,
        plan_name: sub.plan&.name
      } : nil
    }
  end
end
