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

    render_optional_export(account, :export_payments)
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/invoices
  def account_invoices
    account = Account.find(params[:account_id])

    render_optional_export(account, :export_invoices)
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/subscriptions
  def account_subscriptions
    account = Account.find(params[:account_id])

    render_optional_export(account, :export_subscriptions)
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end

  # GET /api/v1/internal/accounts/:account_id/export/files?user_id=
  #
  # GDPR Article 15: the files the DATA SUBJECT uploaded (uploaded_by_id) in
  # this account (account_id), not every file in the account — an export
  # request belongs to one user, and a co-member's files are that co-member's
  # personal data, not the requester's. Soft-deleted rows are included (with
  # deleted_at): the platform still holds them. Metadata only, not file
  # content; exif_data is included because it can hold GPS/location, which is
  # the subject's personal data. storage_key and other internal locators are
  # not personal data and stay out.
  def account_files
    return render_error("user_id is required", status: :unprocessable_content) if params[:user_id].blank?

    account = Account.find(params[:account_id])
    user = User.where(account_id: account.id).find(params[:user_id])
    files = FileManagement::Object.where(account_id: account.id, uploaded_by_id: user.id).order(:created_at)

    render_success(data: files.map { |f| file_data(f) }, meta: { count: files.size })
  rescue ActiveRecord::RecordNotFound => e
    render_not_found(e.model == "User" ? "User" : "Account")
  end

  private

  # Billing records come from an extension that core cannot depend on, so the
  # capability check stays — but an absent provider is reported as such
  # (meta.available: false), never as an account that simply has no records.
  def render_optional_export(account, method_name)
    if account.respond_to?(method_name)
      records = account.public_send(method_name)
      render_success(data: records, meta: { available: true, count: records.size })
    else
      render_success(data: [], meta: { available: false, reason: "no_export_provider_installed" })
    end
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
      filename: file.filename,
      content_type: file.content_type,
      file_type: file.file_type,
      category: file.category,
      file_size: file.file_size,
      visibility: file.visibility,
      version: file.version,
      exif_data: file.exif_data,
      created_at: file.created_at,
      updated_at: file.updated_at,
      deleted_at: file.deleted_at
    }
  end
end
