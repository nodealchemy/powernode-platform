# frozen_string_literal: true

module Compliance
  # Job for processing account terminations after grace period
  # Runs every 6 hours to check for accounts ready for termination
  class AccountTerminationJob < BaseJob
    sidekiq_options queue: 'compliance', retry: 3

    def execute(_args = nil)
      log_info 'Starting account termination processing'

      results = {
        processed: 0,
        reminders_sent: 0,
        errors: []
      }

      # Process terminations ready for deletion
      process_ready_terminations(results)

      # Send reminder notifications
      send_termination_reminders(results)

      log_info "Account termination job complete: #{results[:processed]} processed, #{results[:reminders_sent]} reminders sent"

      # Fail loud: a per-account termination that errored was swallowed into
      # results[:errors] and the job would otherwise return normally, so Sidekiq
      # would see success and retry:3 would never fire — stranding a
      # partially-terminated account. Failed terminations are reverted to
      # 'grace_period' (re-selectable) in process_termination's rescue; succeeded
      # ones are 'completed'/'terminated' (outside the re-fetch filter, so the
      # retry only re-attempts the failed ones). Raise so the failure is surfaced
      # and Sidekiq retries.
      if results[:errors].any?
        failed_ids = results[:errors].map { |error| error[:termination_id] }.join(', ')
        raise "Account termination failed for: #{failed_ids}"
      end

      results
    end

    private

    def process_ready_terminations(results)
      # Fetch terminations ready for processing. BackendApiClient#handle_response
      # returns the parsed JSON body VERBATIM (string keys) on 2xx and raises
      # ApiError on any non-2xx — not a symbol-keyed {success:, data:} envelope
      # (see the matching note in DataDeletionJob#execute). Every response
      # read in this job was symbol-keyed against a string-keyed hash, so it
      # has never actually processed a termination (IMP-b33a3ecca331 review).
      response = api_client.get('/api/v1/internal/account_terminations', {
        status: 'grace_period',
        grace_period_expired: true
      })

      return unless response['success']

      terminations = response['data'] || []

      terminations.each do |termination|
        begin
          process_termination(termination)
          results[:processed] += 1
        rescue => e
          log_error "Failed to process termination #{termination['id']}: #{e.message}"
          results[:errors] << { termination_id: termination['id'], error: e.message }
        end
      end
    end

    def process_termination(termination)
      termination_id = termination['id']
      account_id = termination['account_id']

      log_info "Processing account termination: #{termination_id} (account: #{account_id})"

      # Update status to processing
      patch_termination!(
        termination_id,
        { status: 'processing', processing_started_at: Time.current.iso8601 }
      )

      # Accumulates ONLY the entries THIS run produces. The server now merges
      # these onto the stored log itself (AccountTerminationsController#update
      # / termination_log_append, IMP-b33a3ecca331 third review, BLOCKER 2) —
      # an atomic, locked append rather than a whole-array replace. Seeding
      # this from the fetched `termination['termination_log']` and sending it
      # straight back (the prior fix, second review) is no longer needed and
      # would now double the history on every write; starting from `[]` and
      # sending only new entries as `termination_log_append` is both correct
      # and race-free.
      termination_log = []

      begin
        # Delete account data
        delete_account_data(account_id, termination_log)

        # Update account status. Fork 1 (IMP-b33a3ecca331): operator decision
        # is to mark the account 'cancelled' (the existing accounts.status enum
        # value closest to "this account is done" — no new status, no new
        # column). A narrow, purpose-built action, not a generic PATCH — it
        # takes no payload and is idempotent, so calling it again on retry is
        # safe. This used to PATCH a bare /api/v1/internal/accounts/:id, which
        # has no route (only GET show is/was routed) with status: 'terminated',
        # a value the check constraint has never allowed.
        #
        # Called BEFORE the account_terminations 'completed' write (review
        # follow-up S1): 'completed' terminations are excluded from every
        # re-fetch this job makes (process_ready_terminations' status filter,
        # send_termination_reminders' status filter), so once written there is
        # no automatic retry. Terminating the account first means a failure
        # here still lands in the rescue below and reverts to 'grace_period'
        # (re-selectable); terminating it AFTER would have left the
        # termination record permanently 'completed' while the account itself
        # was never actually cancelled — an inconsistent state with no path
        # back to consistency.
        terminate_account!(account_id)

        # Complete termination
        patch_termination!(
          termination_id,
          {
            status: 'completed',
            completed_at: Time.current.iso8601,
            termination_log_append: termination_log
          }
        )

        log_info "Account #{account_id} termination complete"

        # Send final notification
        send_completion_notification(termination)
      rescue => e
        log_error "Account termination failed: #{e.message}"

        # Re-selectability: revert status from 'processing' back to 'grace_period'
        # so the next run's re-fetch (status: 'grace_period', grace_period_expired:
        # true) re-selects this partially-terminated account instead of stranding
        # it forever in 'processing' (which no query re-selects).
        #
        # patch_termination! itself raises on a failed write — nested
        # begin/rescue so THAT failure can never mask the ORIGINAL error `e`
        # (same defect class as DataDeletionJob, review follow-up
        # IMP-b33a3ecca331). Log the write failure (still visible) and
        # re-raise `e` regardless.
        begin
          patch_termination!(
            termination_id,
            {
              status: 'grace_period',
              termination_log_append: termination_log + [{
                event: 'error',
                error: e.message,
                at: Time.current.iso8601
              }]
            }
          )
        rescue => write_error
          log_error "Failed to revert termination #{termination_id} to grace_period: #{write_error.message}"
        end

        raise e
      end
    end

    # Persisted status writes must never fail silently. IMP-b33a3ecca331 found
    # that the server-side params contract had been dropping every one of
    # these writes (ActionController::ParameterMissing, rescued into a 400 this
    # job never checked) — the fix there is what makes these writes real again,
    # and this raises if that (or any future) write failure ever recurs, so the
    # job's own rescue/retry path takes over instead of silently proceeding as
    # if the state had changed.
    def patch_termination!(termination_id, payload)
      response = api_client.patch("/api/v1/internal/account_terminations/#{termination_id}", payload)
      unless response['success']
        raise "Failed to update account termination #{termination_id}: #{response['error']}"
      end
      response
    end

    # See Api::V1::Internal::AccountsController#terminate — no payload, sets
    # status: 'cancelled', idempotent.
    def terminate_account!(account_id)
      response = api_client.patch("/api/v1/internal/accounts/#{account_id}/terminate", {})
      unless response['success']
        raise "Failed to terminate account #{account_id}: #{response['error']}"
      end
      response
    end

    def delete_account_data(account_id, termination_log)
      # Fetch account users
      users_response = api_client.get("/api/v1/internal/accounts/#{account_id}/users")
      users = users_response['data'] || []

      # Process each user
      users.each do |user|
        delete_user_data(user['id'], termination_log)
      end

      # Delete account-level data
      delete_account_records(account_id, termination_log)
    end

    def delete_user_data(user_id, termination_log)
      # Delete user consents
      response = api_client.delete("/api/v1/internal/users/#{user_id}/consents")
      termination_log << { event: 'deleted_consents', user_id: user_id, at: Time.current.iso8601 }

      # Delete terms acceptances
      api_client.delete("/api/v1/internal/users/#{user_id}/terms_acceptances")
      termination_log << { event: 'deleted_terms_acceptances', user_id: user_id, at: Time.current.iso8601 }

      # Anonymize audit logs
      api_client.patch("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})
      termination_log << { event: 'anonymized_audit_logs', user_id: user_id, at: Time.current.iso8601 }

      # Delete password histories
      api_client.delete("/api/v1/internal/users/#{user_id}/password_histories")

      # Delete user roles
      api_client.delete("/api/v1/internal/users/#{user_id}/roles")

      # Anonymize user record. The internal anonymize endpoint owns the full
      # field list (email/name/status/credentials/PII) — see
      # Api::V1::Internal::UsersController#anonymize — so no payload here.
      # This used to PATCH a bare `/api/v1/internal/users/:id`, which has no
      # route (404) and carried `status: 'terminated'`, a value the users
      # table's `valid_user_status` check constraint has never allowed; every
      # termination therefore failed at this step (IMP-7ff4be3454a6). The
      # routed anonymize endpoint sets status: 'inactive' — the design is
      # anonymize-in-place, not a distinct terminated status.
      api_client.patch("/api/v1/internal/users/#{user_id}/anonymize", {})
      termination_log << { event: 'anonymized_user', user_id: user_id, at: Time.current.iso8601 }
    end

    def delete_account_records(account_id, termination_log)
      # Delete files. Api::V1::Internal::AccountsController#delete_files
      # returns `data: { count: }` (added alongside this fix — it previously
      # returned `message` only, so this read was always 0 regardless of the
      # symbol/string key bug).
      response = api_client.delete("/api/v1/internal/accounts/#{account_id}/files")
      termination_log << {
        event: 'deleted_files',
        count: response['data']&.dig('count') || 0,
        at: Time.current.iso8601
      }

      # Delete API keys
      api_client.delete("/api/v1/internal/accounts/#{account_id}/api_keys")
      termination_log << { event: 'deleted_api_keys', at: Time.current.iso8601 }

      # Delete webhooks
      api_client.delete("/api/v1/internal/accounts/#{account_id}/webhooks")
      termination_log << { event: 'deleted_webhooks', at: Time.current.iso8601 }

      # Delete data export requests
      api_client.delete("/api/v1/internal/accounts/#{account_id}/data_export_requests")
      termination_log << { event: 'deleted_export_requests', at: Time.current.iso8601 }

      # Delete data deletion requests
      api_client.delete("/api/v1/internal/accounts/#{account_id}/data_deletion_requests")
      termination_log << { event: 'deleted_deletion_requests', at: Time.current.iso8601 }

      # Subscription anonymization is a business-extension concern (billing
      # subscriptions only exist when that extension is loaded). Core has no
      # route for this and no generic seam covers it either —
      # Powernode::BillingBridge registers subscription/payment/plan MODELS
      # and a provisioning quota/meter handler, but no anonymize handler.
      # Per IMP-b33a3ecca331 direction: skip cleanly in core mode rather than
      # calling an unrouted endpoint or inventing a new bridge seam; the gap
      # is documented in docs/operations/compliance.md.
      log_info "Skipping subscription anonymization for account #{account_id}: " \
               'no billing extension provider registered (core mode)'
      termination_log << {
        event: 'subscription_anonymize_skipped',
        reason: 'no_billing_extension_provider',
        at: Time.current.iso8601
      }
    end

    def send_termination_reminders(results)
      # Fetch terminations in grace period
      response = api_client.get('/api/v1/internal/account_terminations', {
        status: 'grace_period'
      })

      return unless response['success']

      terminations = response['data'] || []

      terminations.each do |termination|
        grace_period_ends = Time.zone.parse(termination['grace_period_ends_at'])
        days_remaining = ((grace_period_ends - Time.current) / 1.day).ceil

        reminder_type = case days_remaining
                        when 7 then '7_days'
                        when 3 then '3_days'
                        when 1 then '1_day'
                        else nil
                        end

        next unless reminder_type

        # Check if reminder already sent
        termination_log = termination['termination_log'] || []
        reminder_event = "reminder_#{reminder_type}_sent"

        next if termination_log.any? { |e| e['event'] == reminder_event }

        begin
          send_reminder(termination, reminder_type, days_remaining)

          # Update log — append only this reminder's own entry (the fetched
          # `termination_log` above is read-only, used to decide whether this
          # reminder is already due/sent; it is not resent to the server).
          patch_termination!(
            termination['id'],
            {
              termination_log_append: [{
                event: reminder_event,
                at: Time.current.iso8601
              }]
            }
          )

          results[:reminders_sent] += 1
        rescue => e
          log_warn "Failed to send reminder for termination #{termination['id']}: #{e.message}"
        end
      end
    end

    def send_reminder(termination, reminder_type, days_remaining)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          account_id: termination['account_id'],
          type: 'account_termination_reminder',
          data: {
            termination_id: termination['id'],
            reminder_type: reminder_type,
            days_remaining: days_remaining,
            grace_period_ends_at: termination['grace_period_ends_at']
          }
        }
      )
    end

    def send_completion_notification(termination)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          type: 'account_termination_complete',
          email: termination['owner_email'], # Captured before termination
          data: {
            termination_id: termination['id'],
            completed_at: Time.current.iso8601
          }
        }
      )
    rescue => e
      log_warn "Failed to send termination completion notification: #{e.message}"
    end
  end
end
