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
  #
  # IMP-0310a1351dab: a bare `.delete_all` here raised InvalidForeignKey
  # (account_terminations.data_export_request_id references this table, no
  # on_delete) for EVERY termination that had requested a data export —
  # Account::Termination.initiate sets that FK the moment `request_data_export:
  # true` is honoured (termination.rb:56-63). Every such termination's
  # deletion sweep crashed here, permanently.
  #
  # REVIEW ROUND 2 fixed a live regression in round 1's own first attempt:
  # deferring on ANY pending/processing export anywhere in the account (not
  # just the terminating account's OWN requested one) meant an unrelated
  # self-service export elsewhere in the account silently blocked EVERY
  # termination's data deletion — while the worker's log still claimed
  # 'deleted_export_requests' regardless. `own_export_request_id` (optional,
  # sent by the worker as the termination's own data_export_request_id) is
  # now the ONLY row this action will ever defer; every other export row for
  # the account is deleted regardless of its own status — an unrelated
  # export's pending/processing state is not a reason for this endpoint to defer, and
  # the FK it must protect never referenced it in the first place.
  #
  # Fixed two ways, deliberately NOT via a migration (`on_delete: :nullify`
  # would ALSO be sound, but the operator flagged the schema.rb regeneration
  # risk explicitly — a broader, harder-to-review change for no more coverage
  # than this narrower, request-scoped fix already gets):
  #   1. GDPR promise (operator ruling 2026-09-24 — see
  #      DataManagement::ExportRequest#delivered_for_deletion? for the one
  #      place this is decided): the OWN export must be DELIVERED — actually
  #      downloaded, or its 7-day download window elapsed unused — before
  #      its row may be removed. A 'failed' export is never treated as
  #      resolved here; Compliance::AccountTerminationJob is responsible for
  #      resetting and re-queuing it (bounded, then parking the termination)
  #      rather than this endpoint quietly letting it through. Left in place
  #      — deferred, not deleted — and reported back as such, rather than
  #      silently vanishing before the user or the worker has had a chance
  #      to retrieve/resolve it.
  #   2. The dangling FK: for every row that IS being deleted, the
  #      referencing account_terminations.data_export_request_id is cleared
  #      FIRST. This does not touch the export's own audit trail —
  #      DataManagement::ExportRequest#log_export_requested/_completed/_failed
  #      write AuditLog rows keyed to the export's OWN id, independent of
  #      both this FK and the termination row, and are untouched by either
  #      the nullify or the delete below.
  #
  # Transactional and row-locked (review round 2, MED): without a lock, a
  # concurrent writer (DataExportJob completing THIS SAME row between the
  # SELECT that decided "still pending, defer it" and the DELETE that skips
  # it) could race harmlessly here (worst case: a now-resolved export
  # survives one extra sweep) — but the SAME race on the DELETABLE set would
  # let a row DataExportJob just moved to 'processing' be deleted out from
  # under it, which cleanup_file! below would then be racing against a write
  # to file_path on a row about to disappear. `.lock` inside the transaction
  # makes the read-decide-write atomic against that.
  def delete_data_export_requests
    unless defined?(DataManagement::ExportRequest)
      log_internal_audit("account.delete_data_export_requests", "Account", @account.id, account_id: @account.id, records_deleted: 0)
      return render_success(message: "Deleted 0 data export request records")
    end

    own_export_request_id = params[:own_export_request_id].presence
    deferred = false
    count = 0
    archive_paths = []

    DataManagement::ExportRequest.transaction do
      locked_scope = DataManagement::ExportRequest.where(account_id: @account.id).lock

      exempt_id = nil
      if own_export_request_id
        own = locked_scope.find_by(id: own_export_request_id)
        if own && !own.delivered_for_deletion?
          deferred = true
          exempt_id = own.id
        end
      end

      deletable = locked_scope
      deletable = deletable.where.not(id: exempt_id) if exempt_id
      deletable_ids = deletable.pluck(:id)

      if deletable_ids.any?
        Account::Termination.where(data_export_request_id: deletable_ids).update_all(data_export_request_id: nil)
        # Removes the PII file from disk before the row (its only record of
        # the path) is gone. Each row is re-selected individually (not
        # re-using `locked_scope`/`deletable`, both already-materialized
        # relations from the locked read above) purely so #cleanup_file!'s
        # own `update!(file_path: nil)` has a normal, unlocked row to write
        # to — the FOR UPDATE lock taken above already serializes against
        # any concurrent writer for the remainder of this transaction.
        DataManagement::ExportRequest.where(id: deletable_ids).find_each do |row|
          archive_paths << row.file_path if row.file_path.present?
          row.cleanup_file!
        end
        count = DataManagement::ExportRequest.where(id: deletable_ids).delete_all
      end
    end

    # `count` exposed structurally (not just embedded in `message`) so the
    # worker (Compliance::AccountTerminationJob#delete_account_records) can
    # log the real outcome instead of unconditionally recording
    # 'deleted_export_requests' regardless of whether anything was actually
    # deleted — review round 2, item 2.
    #
    # `file_paths` lists the archives the deleted rows pointed at, read before
    # cleanup_file! nulls them: the archive lives on the WORKER host, which
    # this action cannot reach, so the worker removes those itself.
    data = { count: count, deferred: deferred ? 1 : 0, file_paths: archive_paths }
    log_internal_audit(
      "account.delete_data_export_requests", "Account", @account.id,
      account_id: @account.id, records_deleted: count, records_deferred: data[:deferred]
    )
    message = "Deleted #{count} data export request records"
    message += " (1 not yet delivered, deferring its deletion)" if deferred
    render_success(data: data, message: message)
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
