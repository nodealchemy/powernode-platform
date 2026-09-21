# frozen_string_literal: true

# Internal API controller for worker service to fetch and manage account data
class Api::V1::Internal::AccountsController < Api::V1::Internal::InternalBaseController
  before_action :set_account, only: [ :show, :users, :terminate, :anonymize_audit_logs, :anonymize_payments,
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
          plan_name: @account.current_subscription&.plan&.name,
          status: @account.current_subscription&.status,
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

  # PATCH /api/v1/internal/accounts/:account_id/terminate
  #
  # Fork 1 (IMP-b33a3ecca331): what "terminated" means for the account row.
  # `accounts.status` only allows active/cancelled/suspended (the
  # `valid_account_status` check constraint) — there is no 'terminated' value,
  # and none is being added. Operator decision: mark the account 'cancelled',
  # the existing enum value closest to "this account is done" — no migration,
  # no new column. Account has no fitting timestamp column (no cancelled_at /
  # terminated_at); the authoritative WHEN/WHY record is
  # `Account::Termination#completed_at`, already set by
  # Compliance::AccountTerminationJob's own status write to that resource.
  # This is ONE narrowly-named action, not a generic accounts#update — it can
  # only ever do this one thing. Idempotent: calling it on an already-
  # cancelled account succeeds without a redundant write or audit row.
  def terminate
    if @account.cancelled?
      render_success(data: account_status_payload(@account), message: "Account already terminated")
      return
    end

    @account.update!(status: "cancelled")
    log_internal_audit("account.terminate", "Account", @account.id, account_id: @account.id)
    render_success(data: account_status_payload(@account), message: "Account terminated")
  end

  # PATCH /api/v1/internal/accounts/:account_id/anonymize_audit_logs
  def anonymize_audit_logs
    count = AuditLog.where(account_id: @account.id).update_all(
      ip_address: "0.0.0.0",
      user_agent: "anonymized"
    )
    log_internal_audit("account.anonymize_audit_logs", "Account", @account.id, account_id: @account.id, records_affected: count)
    render_success(message: "Anonymized #{count} audit log records")
  end

  # PATCH /api/v1/internal/accounts/:account_id/anonymize_payments
  def anonymize_payments
    count = @account.payments.update_all(
      metadata: nil
    ) if @account.respond_to?(:payments)
    log_internal_audit("account.anonymize_payments", "Account", @account.id, account_id: @account.id, records_affected: count || 0)
    render_success(message: "Anonymized #{count || 0} payment records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/files
  #
  # `data: { count: }` added (IMP-b33a3ecca331 review, S5): the worker reads
  # this count back (Compliance::AccountTerminationJob#delete_account_records)
  # to log how many records were actually deleted — a message-only response
  # gave it nothing structured to read, so that read always saw 0.
  # IMP-bf52b4da135b: this action has NEVER erased a file. It was
  # `@account.files.delete_all if @account.respond_to?(:files)`, and Account
  # declares no `files` association, so the guard was ALWAYS false and every
  # account termination recorded "Deleted 0 file records" — a success-shaped
  # response over an erasure that did not happen, which is exactly why the
  # gap survived this long.
  #
  # It is NOT restored to that shape and NOT implemented here either. Real
  # file erasure is blocked on problems that are their own piece of work, and
  # they are demonstrated rather than asserted (see the reproduction kept with
  # the follow-up task): five tables reference file_objects with no inverse
  # association and no `on_delete`, so destroying a chat-attached file raises
  #   PG::ForeignKeyViolation ... violates foreign key constraint
  #   "fk_rails_ca093e583a" on table "chat_message_attachments"
  # mid-iteration, after shares have already been deleted and with no
  # rollback; FileManagement::Object's after_destroy :remove_from_storage
  # swallows a blob-removal failure, so a naive implementation reports
  # erasure it did not perform; and the same scope holds non-personal
  # platform artifacts (disk_image, sbom_export, attestation_proof,
  # vendor_certificate, ...) that must not be swept up by a data-subject
  # request.
  #
  # So until that lands, this reports the gap HONESTLY instead of hiding it:
  # `erased: false` with a reason, and a message that does not claim a
  # deletion. Same shape as the already-established
  # `subscription_anonymize_skipped` precedent in
  # Compliance::AccountTerminationJob#delete_account_records — an unmet
  # obligation recorded as unmet.
  #
  # Deliberately NOT a 5xx/501: BackendApiClient raises ApiError on any
  # non-2xx, which would abort the whole account termination, and a
  # termination has no path back once it fails. Failing every termination to
  # signal a known, already-documented gap trades a visible gap for a broken
  # pipeline. `count: 0` is retained so the existing worker read keeps
  # working; `erased` is what callers should branch on.
  def delete_files
    log_internal_audit(
      "account.delete_files", "Account", @account.id,
      account_id: @account.id, records_deleted: 0, erased: false, reason: "no_erasure_path"
    )
    render_success(
      data: { count: 0, erased: false, reason: "no_erasure_path" },
      message: "Files were NOT erased: this platform has no erasure path for file objects yet"
    )
  end

  # DELETE /api/v1/internal/accounts/:account_id/api_keys
  def delete_api_keys
    count = @account.api_keys.delete_all if @account.respond_to?(:api_keys)
    log_internal_audit("account.delete_api_keys", "Account", @account.id, account_id: @account.id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} API key records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/webhooks
  def delete_webhooks
    count = @account.webhooks.delete_all if @account.respond_to?(:webhooks)
    log_internal_audit("account.delete_webhooks", "Account", @account.id, account_id: @account.id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} webhook records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/data_export_requests
  def delete_data_export_requests
    count = DataManagement::ExportRequest.where(account_id: @account.id).delete_all if defined?(DataManagement::ExportRequest)
    log_internal_audit("account.delete_data_export_requests", "Account", @account.id, account_id: @account.id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} data export request records")
  end

  # DELETE /api/v1/internal/accounts/:account_id/data_deletion_requests
  def delete_data_deletion_requests
    count = DataManagement::DeletionRequest.where(account_id: @account.id).delete_all if defined?(DataManagement::DeletionRequest)
    log_internal_audit("account.delete_data_deletion_requests", "Account", @account.id, account_id: @account.id, records_deleted: count || 0)
    render_success(message: "Deleted #{count || 0} data deletion request records")
  end

  private

  def account_status_payload(account)
    { id: account.id, status: account.status }
  end

  def set_account
    @account = Account.find(params[:account_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account")
  end
end
