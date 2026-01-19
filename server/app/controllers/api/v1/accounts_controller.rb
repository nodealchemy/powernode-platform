# frozen_string_literal: true

class Api::V1::AccountsController < ApplicationController
  before_action :set_account, only: [ :show, :update ]

  # GET /api/v1/accounts/:id
  def show
    render_success(
      data: account_data(@account)
    )
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

    # Allow access to other accounts only if user has accounts.read permissions
    if params[:id] != current_account.id && !current_user.has_permission?("accounts.read")
      return render_error("Access denied", status: :forbidden)
    end

    @account = Account.find(params[:id]) if params[:id] != current_account.id
  rescue ActiveRecord::RecordNotFound
    render_error("Account not found", status: :not_found)
  end

  def account_params
    params.require(:account).permit(:name, :settings, :billing_email, :tax_id)
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
      subscription: account.subscription ? {
        id: account.subscription.id,
        status: account.subscription.status,
        plan_name: account.subscription.plan.name
      } : nil
    }
  end
end
