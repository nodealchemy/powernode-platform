# frozen_string_literal: true

module Compliance
  # Job for processing GDPR data deletion requests
  class DataDeletionJob < BaseJob
    sidekiq_options queue: :compliance

    # DataManagement::DeletionRequest::DELETABLE_DATA_TYPES names these as
    # canonical GDPR erasure categories, but nothing in core backs them with an
    # actual model (no Activity, per-user Setting, Communication, or Analytics
    # model exists; per-user "files" has no clean association either — see
    # IMP-b33a3ecca331). Calling an endpoint for them would either 404 or
    # silently do nothing; recording a false 'deleted' would misstate what
    # actually happened to a data subject's request. Skip them explicitly and
    # say so in the log, rather than attempt a call.
    UNSUPPORTED_DATA_TYPES = %w[files activity settings communications analytics].freeze

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

      # Check grace period. grace_period_ends_at can be missing — this was
      # ALWAYS true before the matching server-side fix
      # (DataDeletionRequestsController#approve_request never set it at all,
      # S-B) and remains a data-integrity possibility worth guarding even
      # with that fixed. The bare `Time.zone.parse(nil)` this used to be
      # raised TypeError straight into the outer rescue, which wrote 'failed'
      # and re-raised `e` — a Sidekiq retry re-ran this SAME job, hit the
      # SAME nil value, and crashed again: an unbreakable loop, not a
      # retryable failure (IMP-b33a3ecca331 third review, S-B). `return` (not
      # raise) once the terminal write lands, so the job actually terminates.
      grace_period_ends_at_raw = deletion_request['grace_period_ends_at']
      if grace_period_ends_at_raw.blank?
        failure_message = "Deletion request #{deletion_request_id} has no grace_period_ends_at set"
        log_error failure_message
        patch_deletion_request!(deletion_request_id, { status: 'failed', error_message: failure_message })
        return
      end

      grace_period_ends = Time.zone.parse(grace_period_ends_at_raw)
      if grace_period_ends > Time.current
        log_info "Deletion request #{deletion_request_id} still in grace period until #{grace_period_ends}"
        return
      end

      # Update status to processing
      patch_deletion_request!(
        deletion_request_id,
        { status: 'processing', processing_started_at: Time.current.iso8601 }
      )

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
        unless e.is_a?(PartialDeletionFailure)
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

      # Delete each data type
      deletable_types = %w[profile activity files settings consents communications analytics]

      deletable_types.each do |data_type|
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

      # Anonymize audit logs and payments (legally retained)
      anonymize_audit_logs(user_id)
      anonymize_payments(account_id)

      # Anonymize user record
      anonymize_user(user_id)

      [deletion_log, retention_log]
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
    #   * 'profile'    -> the user anonymize action (idempotent with the
    #                      unconditional anonymize_user call process_full_deletion
    #                      already makes after this loop; calling it twice is
    #                      harmless, not fixing that pre-existing redundancy here)
    #   * 'audit_logs' -> the user audit-log anonymize action (only reachable via
    #                      this method for a 'partial' deletion request; 'full'
    #                      handles it separately, unconditionally, below)
    #   * 'payments'   -> the account payment anonymize action (same as above)
    #   * 'consents'   -> the already-routed user consents delete action
    # Types with no backing data model anywhere in core are skipped explicitly
    # (see UNSUPPORTED_DATA_TYPES) rather than attempting a call.
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
      when 'consents'
        # Api::V1::Internal::UsersController#delete_consents returns
        # `data: { count: }` (added alongside this fix — it previously
        # returned `message` only, so this read was always 0 regardless of
        # the symbol/string key bug).
        response = api_client.delete("/api/v1/internal/users/#{user_id}/consents")
        { count: response['data']&.dig('count') || 0 }
      when *UNSUPPORTED_DATA_TYPES
        log_warn "Data type '#{data_type}' has no backing data model in this deployment; " \
                 'recording it as skipped rather than claiming it was deleted'
        { skipped: true, reason: 'no_backing_data_model' }
      else
        log_warn "Unknown data type '#{data_type}' requested for deletion; recording it as skipped"
        { skipped: true, reason: 'unknown_data_type' }
      end
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
        {
          data_type: data_type,
          action: 'deleted',
          records_affected: result[:count],
          processed_at: Time.current.iso8601
        }
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
        'audit_logs' => 'Required for security and compliance auditing'
      }[data_type] || 'Legal retention requirement'
    end

    def notify_user_deletion_complete(deletion_request)
      # Send to a backup email or skip if user is fully anonymized
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          type: 'data_deletion_complete',
          email: deletion_request['user_email'], # Captured before anonymization
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
