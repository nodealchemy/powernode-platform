# frozen_string_literal: true

# Internal API controller for worker service to export user and account data
class Api::V1::Internal::DataExportsController < Api::V1::Internal::InternalBaseController
  # GET /api/v1/internal/users/:user_id/export/profile
  def user_profile
    user = User.find(params[:user_id])

    render_success(data: {
      id: user.id,
      email: user.email,
      name: user.name,
      created_at: user.created_at,
      updated_at: user.updated_at,
      last_login_at: user.last_login_at,
      email_verified: user.email_verified?
    })
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end

  # GET /api/v1/internal/users/:user_id/export/activity
  def user_activity
    user = User.find(params[:user_id])
    activities = user.respond_to?(:activities) ? user.activities.limit(1000) : []

    render_success(data: activities.map { |a| activity_data(a) })
  rescue ActiveRecord::RecordNotFound
    render_not_found("User")
  end

  # GET /api/v1/internal/users/:user_id/export/audit_logs
  def user_audit_logs
    audit_logs = AuditLog.where(user_id: params[:user_id]).limit(1000)

    render_success(data: audit_logs.map { |l| audit_log_data(l) })
  end

  # GET /api/v1/internal/users/:user_id/export/consents
  def user_consents
    consents = UserConsent.where(user_id: params[:user_id])

    render_success(data: consents.map { |c| consent_data(c) })
  end

  # GET /api/v1/internal/accounts/:account_id/export/payments
  def account_payments
    account = Account.find(params[:account_id])

    render_success(data: account.respond_to?(:export_payments) ? account.export_payments : [])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/invoices
  def account_invoices
    account = Account.find(params[:account_id])

    render_success(data: account.respond_to?(:export_invoices) ? account.export_invoices : [])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/subscriptions
  def account_subscriptions
    account = Account.find(params[:account_id])

    render_success(data: account.respond_to?(:export_subscriptions) ? account.export_subscriptions : [])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/files
  def account_files
    account = Account.find(params[:account_id])
    files = account.respond_to?(:files) ? account.files.limit(1000) : []

    render_success(data: files.map { |f| file_data(f) })
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  private

  def activity_data(activity)
    {
      id: activity.id,
      action: activity.respond_to?(:action) ? activity.action : nil,
      created_at: activity.created_at
    }
  end

  def audit_log_data(log)
    {
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      ip_address: log.ip_address,
      created_at: log.created_at
    }
  end

  def consent_data(consent)
    {
      id: consent.id,
      consent_type: consent.consent_type,
      granted: consent.granted,
      granted_at: consent.granted_at,
      revoked_at: consent.revoked_at
    }
  end

  def file_data(file)
    {
      id: file.id,
      filename: file.respond_to?(:filename) ? file.filename : nil,
      size: file.respond_to?(:size) ? file.size : nil,
      created_at: file.created_at
    }
  end
end
