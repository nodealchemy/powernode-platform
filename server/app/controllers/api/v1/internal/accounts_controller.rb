# frozen_string_literal: true

# Internal API controller for worker service to fetch and manage account data
class Api::V1::Internal::AccountsController < Api::V1::Internal::InternalBaseController
  before_action :set_account, only: [ :show, :users, :anonymize_audit_logs, :anonymize_payments,
                                       :delete_files, :delete_api_keys, :delete_webhooks,
                                       :delete_data_export_requests, :delete_data_deletion_requests ]

  # GET /api/v1/internal/accounts/:id
  def show
    owner = @account.owner

    render_success(
      data: {
        account: {
          id: @account.id,
          name: @account.name,
          billing_email: @account.billing_email,
          owner_email: owner&.email,
          owner_name: owner&.name,
          plan_name: @account.subscription&.plan&.name,
          status: @account.subscription&.status,
          system_worker_token: @account.system_worker_token,
          has_system_worker: @account.has_system_worker?,
          created_at: @account.created_at
        }
      }
    )
  end

  # GET /api/v1/internal/accounts/:account_id/users
  def users
    account_users = @account.users

    render_success(
      data: account_users.map { |u| { id: u.id, email: u.email, name: u.name } }
    )
  end

  # PATCH /api/v1/internal/accounts/:account_id/anonymize_audit_logs
  def anonymize_audit_logs
    count = AuditLog.where(account_id: @account.id).update_all(
      ip_address: "0.0.0.0",
      user_agent: "anonymized"
    )
    render_success(message: "Anonymized #{count} audit log records")
  end

  # PATCH /api/v1/internal/accounts/:account_id/anonymize_payments
  def anonymize_payments
    count = @account.payments.update_all(
      metadata: nil,
      billing_details: nil
    ) if @account.respond_to?(:payments)
    render_success(message: "Anonymized #{count || 0} payment records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/files
  def delete_files
    count = @account.files.delete_all if @account.respond_to?(:files)
    render_success(message: "Deleted #{count || 0} file records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/api_keys
  def delete_api_keys
    count = @account.api_keys.delete_all if @account.respond_to?(:api_keys)
    render_success(message: "Deleted #{count || 0} API key records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/webhooks
  def delete_webhooks
    count = @account.webhooks.delete_all if @account.respond_to?(:webhooks)
    render_success(message: "Deleted #{count || 0} webhook records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/data_export_requests
  def delete_data_export_requests
    count = DataManagement::ExportRequest.where(account_id: @account.id).delete_all if defined?(DataManagement::ExportRequest)
    render_success(message: "Deleted #{count || 0} data export request records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/data_deletion_requests
  def delete_data_deletion_requests
    count = DataManagement::DeletionRequest.where(account_id: @account.id).delete_all if defined?(DataManagement::DeletionRequest)
    render_success(message: "Deleted #{count || 0} data deletion request records")
  end

  private

  def set_account
    @account = Account.find(params[:id] || params[:account_id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end
end
