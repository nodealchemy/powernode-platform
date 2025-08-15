# frozen_string_literal: true

class Api::V1::AccountsController < ApplicationController
  before_action :set_account, only: [ :show, :update ]

  # GET /api/v1/accounts/:id
  def show
    render json: {
      success: true,
      data: account_data(@account)
    }, status: :ok
  end

  # PATCH/PUT /api/v1/accounts/:id
  def update
    if @account.update(account_params)
      render json: {
        success: true,
        data: account_data(@account),
        message: "Account updated successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Account update failed",
        details: @account.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  private

  def set_account
    @account = current_account

    # Allow access to other accounts only if user has accounts.read permissions
    if params[:id] != current_account.id && !current_user.has_permission?("accounts.read")
      return render json: {
        success: false,
        error: "Access denied"
      }, status: :forbidden
    end

    @account = Account.find(params[:id]) if params[:id] != current_account.id
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: "Account not found"
    }, status: :not_found
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
