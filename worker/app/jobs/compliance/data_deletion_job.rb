# frozen_string_literal: true

module Compliance
  # Job for processing GDPR data deletion requests
  class DataDeletionJob < BaseJob
    include ComplianceFileErasureConcern

    sidekiq_options queue: :compliance

    # 'activity' and 'analytics' are WITHDRAWN from
    # DataManagement::DeletionRequest::DELETABLE_DATA_TYPES
    # (IMP-bf52b4da135b) — the server no longer advertises them and rejects
    # them on create. See that constant's comment for the per-type reasoning;
    # in short, neither has a category-level erasure path at all.
    #
    # They stay listed HERE, rather than being deleted outright, because rows
    # created BEFORE that withdrawal can still carry them and this job must
    # process those rows without either 404ing or — far worse — recording a
    # false 'deleted'. This list is now purely a legacy-row compatibility
    # path; nothing new can enter it.
    #
    # The three this constant used to name besides them — settings,
    # communications, and (IMP-d97f6e3bbc2b) files — DO have a backing model
    # with a real erasure path (the users preference columns; Notification +
    # EmailDelivery; FileManagement::Erasure) and are routed to real
    # endpoints in #delete_data_type. Recording those as skipped was accurate
    # about the job's behaviour and wrong about the world: the data existed
    # and survived the erasure.
    UNSUPPORTED_DATA_TYPES = %w[activity analytics].freeze

    # Mirrors the server's DataManagement::DeletionRequest::DELETABLE_DATA_TYPES
    # (same members, same order) — the categories the platform advertises as
    # erasable. A 'full' deletion walks EVERY member through the one per-type
    # loop in #process_full_deletion, so data_types_to_retain binds each of
    # them the same way (IMP-ca3551dd27be). Duplicated rather than fetched
    # because the worker reaches the server over the HTTP API only and never
    # shares its models; spec/jobs/compliance/
    # data_deletion_job_deletable_types_drift_spec.rb fails if the two lists
    # diverge.
    DELETABLE_DATA_TYPES = %w[
      profile
      audit_logs
      payments
      settings
      consents
      communications
      files
    ].freeze

    # A per-data-type deletion failure (IMP-b33a3ecca331 third review, S-C).
    # Distinct from the plain `raise failure_message` this used to be so the
    # outer rescue can tell "this path already wrote 'failed' with the full
    # deletion_log/retention_log detail, and status is now terminal" apart
    # from every OTHER error class it catches (a raised StandardError from
    # deep in process_*_deletion, an ApiError, ...), which have NOT written
    # anything yet and still need the outer rescue's own 'failed' write.
    # Skipping that redundant second write also sidesteps the S-A/S3 guard
    # now rejecting failed->failed as an illegal no-op transition.
    class PartialDeletionFailure < StandardError; end

    # An OPERATIONAL per-type failure (IMP-d97f6e3bbc2b, critic B M2): the
    # files erasure reported a blob the storage provider could not remove —
    # the store is down, unmounted or misconfigured. Unlike a policy outcome
    # (a held file) this is exactly what a retry exists for, and the data
    # subject, anonymized by now, cannot re-file. So it must NOT end the
    # request 'failed' (terminal, no re-arm): the outer rescue records the
    # error on the still-'processing' row and re-raises so Sidekiq's retry
    # resumes it. When the retries are exhausted the job lands in the dead
    # set and the request stays 'processing' with error_message set; an
    # operator re-runs it once storage is back (docs/operations/compliance.md).
    class RetryableErasureFailure < StandardError; end

    def execute(deletion_request_id)
      log_info "Processing data deletion request: #{deletion_request_id}"

      # Fetch deletion request from API. BackendApiClient#handle_response
      # returns the parsed JSON body VERBATIM (string keys) on 2xx and raises
      # ApiError on any non-2xx (worker/app/services/backend_api_client.rb) —
      # this is NOT a symbol-keyed {success:, data:} envelope. Read it the way
      # the rest of the worker does (e.g. Ai::ApprovalExpiryJob): string keys.
      # (IMP-b33a3ecca331 review: every response read in this job was using
      # symbol keys against a string-keyed hash, so `response[:success]` /
      # `response[:data]` were always nil — this job has never actually run
      # correctly; worker specs stub symbol-keyed doubles, which is why it
      # wasn't caught.)
      #
      # The show action also wraps the resource one level deeper —
      # `render_success({ data_deletion_request: {...} })` — so the response
      # body is `{"success"=>true,"data"=>{"data_deletion_request"=>{...}}}`,
      # not `{"success"=>true,"data"=>{...}}`. Unwrap both levels.
      response = api_client.get("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")

      unless response['success']
        raise "Failed to fetch deletion request: #{response['error']}"
      end

      deletion_request = response['data'] && response['data']['data_deletion_request']
      unless deletion_request
        raise "Failed to fetch deletion request #{deletion_request_id}: empty response payload"
      end

      # Verify ready for processing. 'processing' is accepted alongside
      # 'approved' so a Sidekiq retry RESUMES a request a prior attempt left
      # mid-flight (see the outer rescue below) instead of silently skipping
      # it — every per-type operation this job performs is idempotent
      # (delete_all / anonymize-in-place), so re-running is safe.
      unless %w[approved processing].include?(deletion_request['status'])
        log_info "Deletion request #{deletion_request_id} is not approved or processing, skipping"
        return
      end

      # Check grace period. The grace period is the data subject's cancellation
      # window (a promise), so this job NEVER starts processing inside it and
      # never bypasses it — and it writes NOTHING when it declines: not
      # 'processing', and above all not 'failed'. A request that was never
      # processed is not failed; 'failed' would drop it out of the privacy
      # controller's `.active` guard and be shown to the data subject as a
      # failed erasure (IMP-26adf1c79c7a).
      #
      # This check is only a PRE-check. The server is the authority — it
      # refuses the approved -> processing transition itself (see
      # #request_processing_start!), so a stale clock or a skipped check here
      # cannot start an early deletion.
      #
      # grace_period_ends_at can be missing (approve_request set none before
      # IMP-b33a3ecca331 S-B; still a data-integrity possibility). It fails
      # CLOSED: an unknown end is not an ended grace period. `return` (not
      # raise), so a Sidekiq retry does not re-crash on the same value; the
      # error is logged for whoever repairs the row.
      grace_period_ends_at_raw = deletion_request['grace_period_ends_at']
      if grace_period_ends_at_raw.blank?
        log_error "Deletion request #{deletion_request_id} has no grace_period_ends_at set; " \
                  'refusing to process (no status write)'
        return
      end

      grace_period_ends = Time.zone.parse(grace_period_ends_at_raw)
      if grace_period_ends > Time.current
        log_info "Deletion request #{deletion_request_id} still in grace period until #{grace_period_ends}"
        return
      end

      # Update status to processing. For an 'approved' request this is the
      # server-enforced start; a refusal means processing must not begin.
      return unless request_processing_start!(deletion_request_id, deletion_request['status'])

      begin
        deletion_log = []
        retention_log = []

        # Process deletion based on type
        case deletion_request['deletion_type']
        when 'full'
          deletion_log, retention_log = process_full_deletion(deletion_request)
        when 'partial'
          deletion_log = process_partial_deletion(deletion_request)
        when 'anonymize'
          deletion_log = process_anonymization(deletion_request)
        end

        # GDPR/compliance safety: a per-data-type erasure that did not succeed
        # must NEVER be reported as a completed deletion. Surface the partial
        # failure (with per-type detail) and raise — NOT because a Sidekiq
        # retry will fix anything (the write below already made this request
        # terminally 'failed'; the guard at the top of #execute skips any
        # future retry outright since 'failed' isn't 'approved'/'processing')
        # but so the failure is visible to whatever surfaces raised job
        # errors (paging/monitoring) instead of the job silently returning
        # having left PII undeleted. `PartialDeletionFailure` (S-C) marks this
        # as a write that already happened, distinct from every other error
        # this method can raise.
        failed_deletions = deletion_log.select { |entry| entry[:action] == 'failed' }
        if failed_deletions.any?
          failed_types = failed_deletions.map { |entry| entry[:data_type] }.join(', ')
          failure_message = "Data deletion failed for: #{failed_types}"

          patch_deletion_request!(
            deletion_request_id,
            {
              status: 'failed',
              deletion_log: deletion_log,
              retention_log: retention_log,
              error_message: failure_message
            }
          )

          raise PartialDeletionFailure, failure_message
        end

        # Complete the request
        patch_deletion_request!(
          deletion_request_id,
          {
            status: 'completed',
            completed_at: Time.current.iso8601,
            deletion_log: deletion_log,
            retention_log: retention_log
          }
        )

        log_info "Data deletion #{deletion_request_id} completed successfully"

        # Send completion notification
        notify_user_deletion_complete(deletion_request)
      rescue => e
        log_error "Data deletion failed: #{e.message}"

        # Terminal state, not a dangling 'processing': a request left in
        # 'processing' with only error_message set was invisible to the old
        # 'approved'-only guard above, so a Sidekiq retry would see a status
        # that isn't 'approved' and silently skip it forever (IMP-b33a3ecca331).
        # 'failed' is terminal and FINAL — unlike account termination's
        # grace_period revert, there is no re-arm path. `approve_request`
        # requires `pending?` and `execute_request` requires `approved?`
        # (data_deletion_requests_controller.rb); 'failed' matches neither, so
        # no admin action_type transitions it back to something this job
        # would ever pick up again. A user whose deletion failed must file a
        # new request (Api::V1::PrivacyController#request_deletion) — its
        # `DataManagement::DeletionRequest.active` guard already excludes
        # 'failed', so a fresh request is not blocked by the dead one.
        #
        # patch_deletion_request! itself raises on a failed write — nested
        # begin/rescue so THAT failure can never mask the ORIGINAL error `e`
        # (review follow-up, IMP-b33a3ecca331). A bare `patch_deletion_request!`
        # here would let a write failure replace `e` on the next `raise`,
        # reporting "the status write failed" when the real story is "the
        # deletion failed AND we couldn't even record that" — losing the
        # domain error entirely. Log the write failure (still visible) and
        # re-raise `e` regardless.
        #
        # Skip this write entirely for PartialDeletionFailure (S-C,
        # IMP-b33a3ecca331 third review): that path already wrote 'failed'
        # (with the full deletion_log/retention_log this generic write
        # doesn't have) before raising. Writing it again here would both
        # lose that detail (this write's payload carries only error_message)
        # and now 422 outright under the S-A/S3 transition guard, since
        # failed -> failed is not an allowed transition.
        #
        # A RetryableErasureFailure is the one error that must NOT become
        # 'failed': the request stays 'processing' (which the guard at the
        # top of #execute resumes on Sidekiq's retry) and only error_message
        # is written — a status-less, status-adjacent write the server
        # permits while processing — so the state is visible to an operator
        # if the retries run out.
        if e.is_a?(RetryableErasureFailure)
          begin
            patch_deletion_request!(deletion_request_id, { error_message: e.message })
          rescue => write_error
            log_error "Failed to record the retryable erasure failure for deletion request " \
                      "#{deletion_request_id}: #{write_error.message}"
          end
        elsif !e.is_a?(PartialDeletionFailure)
          begin
            patch_deletion_request!(
              deletion_request_id,
              { status: 'failed', error_message: e.message }
            )
          rescue => write_error
            log_error "Failed to persist 'failed' status for deletion request " \
                      "#{deletion_request_id}: #{write_error.message}"
          end
        end

        raise e
      end
    end

    private

    # Server refusals of an approved -> processing start that mean "do not
    # process", not "something broke": the grace period has not ended (or its
    # end is unset), or another starter (run-now / a second worker) already
    # moved the row out of 'approved'. Either way this job exits WITHOUT any
    # status write.
    START_REFUSAL_CODES = %w[GRACE_PERIOD_NOT_ENDED INVALID_STATUS_TRANSITION].freeze

    # Requests the (server-enforced) transition to 'processing'. Returns true
    # when processing may proceed, false when the server refused the start.
    # Only an 'approved' request is starting; a 'processing' one is a Sidekiq
    # retry resuming, whose PATCH is processing -> processing. Every other
    # failure still raises exactly as patch_deletion_request! always did.
    def request_processing_start!(deletion_request_id, current_status)
      patch_deletion_request!(
        deletion_request_id,
        { status: 'processing', processing_started_at: Time.current.iso8601 }
      )
      true
    rescue BackendApiClient::ApiError => e
      raise unless current_status == 'approved' && start_refused?(e)

      log_warn "Server refused to start deletion request #{deletion_request_id} (#{e.message}); " \
               'not processing, no status write'
      false
    end

    def start_refused?(error)
      body = error.response_body
      error.status == 422 && body.is_a?(Hash) && START_REFUSAL_CODES.include?(body['code'])
    end

    # Persisted status writes must never fail silently. IMP-b33a3ecca331 found
    # that the server-side params contract had been dropping every one of
    # these writes (ActionController::ParameterMissing, rescued into a 400 this
    # job never checked) — the fix there is what makes these writes real again,
    # and this raises if that (or any future) write failure ever recurs, so the
    # job's own rescue/retry path takes over instead of silently proceeding as
    # if the state had changed.
    def patch_deletion_request!(deletion_request_id, payload)
      response = api_client.patch("/api/v1/internal/data_deletion_requests/#{deletion_request_id}", payload)
      unless response['success']
        raise "Failed to update data deletion request #{deletion_request_id}: #{response['error']}"
      end
      response
    end

    def process_full_deletion(deletion_request)
      user_id = deletion_request['user_id']
      account_id = deletion_request['account_id']
      data_types_to_retain = deletion_request['data_types_to_retain'] || []

      deletion_log = []
      retention_log = []

      # Every DELETABLE_DATA_TYPES member goes through this ONE loop: retained
      # -> a retention_log entry and its endpoint is never called; otherwise
      # -> erased/anonymized by #delete_data_type and recorded in deletion_log
      # (a failure there is a per-type 'failed' entry, surfaced below as a
      # PartialDeletionFailure). 'activity' and 'analytics' are not walked:
      # they were withdrawn from the server constant (IMP-bf52b4da135b).
      DELETABLE_DATA_TYPES.each do |data_type|
        if data_types_to_retain.include?(data_type)
          retention_log << {
            data_type: data_type,
            reason: retention_reason_for(data_type),
            processed_at: Time.current.iso8601
          }
        else
          deletion_log << deletion_log_entry(data_type, delete_data_type(data_type, user_id, account_id))
        end
      end

      # NOTE (IMP-bf52b4da135b, IMP-ca3551dd27be): there used to be
      # UNCONDITIONAL `anonymize_user`, `anonymize_audit_logs` and
      # `anonymize_payments` calls here, after the loop. Each one anonymized
      # its category even when the request RETAINED it (the retention_log
      # said "retained" — or, for audit_logs/payments, said nothing at all —
      # while the data was anonymized anyway), and the audit-log/payment ones
      # were never recorded in the deletion_log. All three categories are
      # DELETABLE_DATA_TYPES members, so the loop above now handles them:
      # anonymized exactly once when not retained, untouched when retained.

      [ deletion_log, retention_log ]
    end

    def process_partial_deletion(deletion_request)
      user_id = deletion_request['user_id']
      account_id = deletion_request['account_id']
      data_types = deletion_request['data_types_to_delete'] || []

      deletion_log = []

      data_types.each do |data_type|
        deletion_log << deletion_log_entry(data_type, delete_data_type(data_type, user_id, account_id))
      end

      deletion_log
    end

    def process_anonymization(deletion_request)
      user_id = deletion_request['user_id']
      account_id = deletion_request['account_id']

      deletion_log = []

      # Anonymize user
      anonymize_user(user_id)
      deletion_log << { data_type: 'user', action: 'anonymized', processed_at: Time.current.iso8601 }

      # Anonymize audit logs
      anonymize_audit_logs(user_id)
      deletion_log << { data_type: 'audit_logs', action: 'anonymized', processed_at: Time.current.iso8601 }

      # Anonymize payments
      anonymize_payments(account_id)
      deletion_log << { data_type: 'payments', action: 'anonymized', processed_at: Time.current.iso8601 }

      deletion_log
    end

    # There is no /api/v1/internal/data_deletion/:type route — it never
    # existed. Point each real data type at the routed action that already
    # performs it instead of inventing a new generic endpoint (IMP-b33a3ecca331):
    #   * 'profile'    -> the user anonymize action
    #   * 'audit_logs' -> the user audit-log anonymize action
    #   * 'payments'   -> the account payment anonymize action
    #   * 'consents'   -> the already-routed user consents delete action
    #   * 'settings' / 'communications' -> the per-user erasure actions added
    #                      in IMP-bf52b4da135b, backed by the users
    #                      preference columns and by Notification +
    #                      EmailDelivery respectively. Both return the same
    #                      `data: { count: }` shape as 'consents'.
    #   * 'files'      -> the per-user files erasure (IMP-d97f6e3bbc2b),
    #                      batched: walked to the end through
    #                      ComplianceFileErasureConcern. A file the server
    #                      could not erase is a FAILED erasure of the
    #                      category, whatever the rest of the batch did.
    # Withdrawn types — reachable only on a legacy row — are skipped
    # explicitly (see UNSUPPORTED_DATA_TYPES) rather than attempting a call
    # to an endpoint that does not exist.
    def delete_data_type(data_type, user_id, account_id)
      case data_type
      when 'profile'
        anonymize_user(user_id)
        { anonymized: true }
      when 'audit_logs'
        anonymize_audit_logs(user_id)
        { anonymized: true }
      when 'payments'
        anonymize_payments(account_id)
        { anonymized: true }
      when 'consents', 'settings', 'communications'
        # Api::V1::Internal::UsersController's per-type delete actions each
        # return `data: { count: }` (the consents one gained it alongside
        # IMP-b33a3ecca331 — it previously returned `message` only, so this
        # read was always 0 regardless of the symbol/string key bug).
        response = api_client.delete("/api/v1/internal/users/#{user_id}/#{data_type}")
        { count: response['data']&.dig('count') || 0 }
      when 'files'
        delete_files(user_id)
      when *UNSUPPORTED_DATA_TYPES
        # Reached only by a legacy row: this type is withdrawn, so nothing
        # new can name it. The wording deliberately does NOT claim the data
        # does not exist — for 'files' it demonstrably does
        # (FileManagement::Object); what is missing is a safe erasure path.
        log_warn "Data type '#{data_type}' is withdrawn — this platform has no erasure path for it; " \
                 'recording it as skipped rather than claiming it was deleted'
        # Renamed from 'no_backing_data_model' (IMP-bf52b4da135b). This value
        # is persisted into the `deletion_log` of real requests — a retained
        # COMPLIANCE artifact that a data subject, an operator or a regulator
        # reads. A wrong comment misleads a developer; a wrong value here
        # misleads the person the record exists to protect, which is why this
        # is worth a contract change rather than a comment.
        #
        # 'no_backing_data_model' became false once 'files' joined this list:
        # FileManagement::Object demonstrably exists. What is actually absent
        # is a safe erasure PATH, which is what the new value names, and which
        # is true for all three withdrawn types.
        #
        # A FORWARD rename only: rows already stored keep the old value, and
        # for those rows it was never accurate to read as "nothing to erase".
        # Before this change the list was files/activity/settings/
        # communications/analytics, so a request that named files, settings
        # or communications was recorded as skipped ('no_backing_data_model')
        # although FileManagement::Object, Notification and EmailDelivery
        # exist. Nothing re-processes those rows; a subject whose completed
        # request named one of those types has not had that data erased by it.
        { skipped: true, reason: 'no_erasure_path' }
      else
        log_warn "Unknown data type '#{data_type}' requested for deletion; recording it as skipped"
        { skipped: true, reason: 'unknown_data_type' }
      end
    rescue RetryableErasureFailure
      # Operational, not a per-type 'failed' entry: propagates to #execute's
      # outer rescue, which keeps the request retryable.
      raise
    rescue => e
      log_warn "Failed to process #{data_type}: #{e.message}"
      { count: 0, error: e.message }
    end

    # Build a deletion-log entry that distinguishes a genuine zero-record delete
    # (nothing matched) from a FAILED delete, an ANONYMIZED record, and a type
    # SKIPPED for lack of a backing data model. A swallowed failure must not be
    # recorded as a successful `action: 'deleted', records_affected: 0`, and a
    # skip must not be recorded as `action: 'deleted'` either — both would
    # misstate what happened to the data subject's request.
    def deletion_log_entry(data_type, result)
      if result[:skipped]
        {
          data_type: data_type,
          action: 'skipped',
          reason: result[:reason],
          processed_at: Time.current.iso8601
        }
      elsif result[:error]
        {
          data_type: data_type,
          action: 'failed',
          error: result[:error],
          processed_at: Time.current.iso8601
        }
      elsif result[:anonymized]
        {
          data_type: data_type,
          action: 'anonymized',
          processed_at: Time.current.iso8601
        }
      else
        entry = {
          data_type: data_type,
          action: 'deleted',
          records_affected: result[:count],
          processed_at: Time.current.iso8601
        }
        entry[:retained_platform_artifacts] = result[:retained_platform_artifacts] if result.key?(:retained_platform_artifacts)
        entry
      end
    end

    # The internal anonymize endpoint owns the full field list (email/name/
    # status/credentials/PII) — see Api::V1::Internal::UsersController
    # #anonymize — so no payload here. The `status: 'deleted'` this used to
    # send was never a value the users table's `valid_user_status` check
    # constraint allowed; the endpoint sets status: 'inactive' (design is
    # anonymize-in-place, not a distinct deleted status).
    def anonymize_user(user_id)
      api_client.patch("/api/v1/internal/users/#{user_id}/anonymize", {})
    end

    def anonymize_audit_logs(user_id)
      api_client.patch(
        "/api/v1/internal/users/#{user_id}/anonymize_audit_logs",
        {}
      )
    end

    # An OLDER server build has no users/:id/files route at all (the route
    # arrived with the erasure path), so what it answers is a 404; that is
    # recorded as the skip it is — `no_erasure_path`, exactly what the
    # withdrawn type used to record — rather than becoming a terminal
    # 'failed' after `profile` was already anonymized (critic B, H2).
    #
    # Otherwise, two kinds of file the server could not erase, kept apart
    # (critic B, M2):
    #   * HELD by a referent — a policy outcome no retry clears. The
    #     subject's file is still there, so the category is a failed
    #     erasure and the request ends 'failed' with the reason on record.
    #   * ERROR — the provider did not remove the blob (store down,
    #     unmounted). Operational: raised as RetryableErasureFailure so the
    #     request stays 'processing' and Sidekiq's retry resumes it. Error
    #     wins over held when both occur — once the store is back the retry
    #     settles the held files as a terminal failure.
    # Ids only in either message, never a filename, and bounded to a sample.
    def delete_files(user_id)
      result = erase_files_in_batches("/api/v1/internal/users/#{user_id}/files")

      if result[:errors].any?
        raise RetryableErasureFailure,
              "files: #{result[:errors].size} file(s) not erased: #{file_erasure_failure_summary(result[:errors])}"
      end

      if result[:held].any?
        return {
          count: result[:count],
          error: "#{result[:held].size} file(s) held: #{file_erasure_failure_summary(result[:held])}"
        }
      end

      # retained_platform_artifacts lands in the subject's deletion_log: the
      # record must say that some of their uploads were kept as platform
      # artifacts, not only how many were erased.
      { count: result[:count], retained_platform_artifacts: result[:retained_platform_artifacts] }
    rescue BackendApiClient::ApiError => e
      raise unless e.status == 404

      log_warn "The server has no files erasure route (404); recording files as skipped rather than erased"
      { skipped: true, reason: 'no_erasure_path' }
    end

    def anonymize_payments(account_id)
      api_client.patch(
        "/api/v1/internal/accounts/#{account_id}/anonymize_payments",
        {}
      )
    end

    def retention_reason_for(data_type)
      {
        'financial_records' => 'Required for tax and accounting purposes',
        'tax_documents' => 'Required by tax regulations',
        'legal_agreements' => 'Required for contract enforcement',
        'audit_logs' => 'Required for security and compliance auditing',
        'payments' => 'Required for tax and accounting purposes'
      }[data_type] || 'Legal retention requirement'
    end

    def notify_user_deletion_complete(deletion_request)
      # The user's own email is erased by this very job, so the notice goes to
      # the address the server snapshotted at request time and returned on the
      # show read at the top of #execute (IMP-b719328ddeb9). The server scrubs
      # it when the request completes; this copy is the only one left, and is
      # never logged. A row with none (legacy) is warned about, not failed: the
      # erasure has already happened and completed.
      address = deletion_request['notification_email']
      if address.blank?
        log_warn "Deletion request #{deletion_request['id']} has no notification address on file; " \
                 'skipping the completion notification'
        return
      end

      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          type: 'data_deletion_complete',
          email: address,
          data: {
            deletion_id: deletion_request['id'],
            completed_at: Time.current.iso8601
          }
        }
      )
    rescue => e
      log_warn "Failed to send deletion completion notification: #{e.message}"
    end
  end
end
