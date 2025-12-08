# frozen_string_literal: true

module Compliance
  # Job for processing account terminations after grace period
  # Runs every 6 hours to check for accounts ready for termination
  class AccountTerminationJob < BaseJob
    queue_as :compliance

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

      results
    end

    private

    def process_ready_terminations(results)
      # Fetch terminations ready for processing
      response = api_client.get('/api/v1/internal/account_terminations', {
        status: 'grace_period',
        grace_period_expired: true
      })

      return unless response[:success]

      terminations = response[:data] || []

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
      api_client.patch(
        "/api/v1/internal/account_terminations/#{termination_id}",
        { status: 'processing', processing_started_at: Time.current.iso8601 }
      )

      termination_log = []

      begin
        # Delete account data
        delete_account_data(account_id, termination_log)

        # Complete termination
        api_client.patch(
          "/api/v1/internal/account_terminations/#{termination_id}",
          {
            status: 'completed',
            completed_at: Time.current.iso8601,
            termination_log: termination_log
          }
        )

        # Update account status
        api_client.patch(
          "/api/v1/internal/accounts/#{account_id}",
          {
            status: 'terminated',
            terminated_at: Time.current.iso8601
          }
        )

        log_info "Account #{account_id} termination complete"

        # Send final notification
        send_completion_notification(termination)
      rescue => e
        log_error "Account termination failed: #{e.message}"

        api_client.patch(
          "/api/v1/internal/account_terminations/#{termination_id}",
          {
            termination_log: termination_log + [{
              event: 'error',
              error: e.message,
              at: Time.current.iso8601
            }]
          }
        )

        raise
      end
    end

    def delete_account_data(account_id, termination_log)
      # Fetch account users
      users_response = api_client.get("/api/v1/internal/accounts/#{account_id}/users")
      users = users_response[:data] || []

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

      # Anonymize user record
      anonymous_email = "terminated_#{SecureRandom.hex(8)}@terminated.powernode.local"
      api_client.patch(
        "/api/v1/internal/users/#{user_id}",
        {
          email: anonymous_email,
          name: 'Terminated User',
          password_digest: nil,
          status: 'terminated',
          two_factor_secret: nil,
          backup_codes: nil,
          last_login_ip: nil,
          preferences: {},
          notification_preferences: {}
        }
      )
      termination_log << { event: 'anonymized_user', user_id: user_id, at: Time.current.iso8601 }
    end

    def delete_account_records(account_id, termination_log)
      # Delete files
      response = api_client.delete("/api/v1/internal/accounts/#{account_id}/files")
      termination_log << {
        event: 'deleted_files',
        count: response[:data]&.dig('count') || 0,
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

      # Anonymize subscription
      api_client.patch(
        "/api/v1/internal/accounts/#{account_id}/subscription/anonymize",
        {}
      )
      termination_log << { event: 'anonymized_subscription', at: Time.current.iso8601 }
    end

    def send_termination_reminders(results)
      # Fetch terminations in grace period
      response = api_client.get('/api/v1/internal/account_terminations', {
        status: 'grace_period'
      })

      return unless response[:success]

      terminations = response[:data] || []

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

          # Update log
          api_client.patch(
            "/api/v1/internal/account_terminations/#{termination['id']}",
            {
              termination_log: termination_log + [{
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
