# frozen_string_literal: true

module Compliance
  # Job for processing GDPR data deletion requests
  class DataDeletionJob < BaseJob
    queue_as :compliance

    def execute(deletion_request_id)
      log_info "Processing data deletion request: #{deletion_request_id}"

      # Fetch deletion request from API
      response = api_client.get("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")

      unless response[:success]
        raise "Failed to fetch deletion request: #{response[:error]}"
      end

      deletion_request = response[:data]

      # Verify ready for processing
      unless deletion_request['status'] == 'approved'
        log_info "Deletion request #{deletion_request_id} is not approved, skipping"
        return
      end

      # Check grace period
      grace_period_ends = Time.zone.parse(deletion_request['grace_period_ends_at'])
      if grace_period_ends > Time.current
        log_info "Deletion request #{deletion_request_id} still in grace period until #{grace_period_ends}"
        return
      end

      # Update status to processing
      api_client.patch(
        "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
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

        # Complete the request
        api_client.patch(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
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

        api_client.patch(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          { error_message: e.message }
        )

        raise
      end
    end

    private

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
          result = delete_data_type(data_type, user_id, account_id)
          deletion_log << {
            data_type: data_type,
            action: 'deleted',
            records_affected: result[:count],
            processed_at: Time.current.iso8601
          }
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
        result = delete_data_type(data_type, user_id, account_id)
        deletion_log << {
          data_type: data_type,
          action: 'deleted',
          records_affected: result[:count],
          processed_at: Time.current.iso8601
        }
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

    def delete_data_type(data_type, user_id, account_id)
      response = api_client.delete(
        "/api/v1/internal/data_deletion/#{data_type}",
        { user_id: user_id, account_id: account_id }
      )

      { count: response[:data]&.dig('deleted_count') || 0 }
    rescue => e
      log_warn "Failed to delete #{data_type}: #{e.message}"
      { count: 0, error: e.message }
    end

    def anonymize_user(user_id)
      anonymous_email = "deleted_#{SecureRandom.hex(8)}@deleted.powernode.local"

      api_client.patch(
        "/api/v1/internal/users/#{user_id}/anonymize",
        {
          email: anonymous_email,
          name: 'Deleted User',
          status: 'deleted'
        }
      )
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
