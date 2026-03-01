# frozen_string_literal: true

module Compliance
  # Daily job for enforcing data retention policies
  # Runs at 2 AM daily to process expired data
  class DataRetentionEnforcementJob < BaseJob
    sidekiq_options queue: :compliance

    def execute(_args = nil)
      log_info 'Starting data retention enforcement'

      # Fetch active retention policies
      response = api_client.get('/api/v1/internal/data_retention_policies', { active: true })

      unless response[:success]
        raise "Failed to fetch retention policies: #{response[:error]}"
      end

      policies = response[:data] || []
      results = {
        policies_processed: 0,
        records_processed: 0,
        errors: []
      }

      policies.each do |policy|
        begin
          result = enforce_policy(policy)
          results[:policies_processed] += 1
          results[:records_processed] += result[:records_processed]
        rescue => e
          log_error "Failed to enforce policy #{policy['id']}: #{e.message}"
          results[:errors] << { policy_id: policy['id'], error: e.message }
        end
      end

      log_info "Data retention enforcement complete: #{results[:policies_processed]} policies, #{results[:records_processed]} records"

      # Log compliance event
      api_client.post(
        '/api/v1/internal/audit_logs',
        {
          action: 'compliance_check',
          resource_type: 'DataRetentionPolicy',
          resource_id: 'enforcement_job',
          source: 'worker',
          metadata: results
        }
      )

      results
    end

    private

    def enforce_policy(policy)
      data_type = policy['data_type']
      retention_days = policy['retention_days']
      action = policy['action']
      account_id = policy['account_id'] # nil for system-wide

      cutoff_date = retention_days.days.ago.iso8601

      log_info "Enforcing #{action} for #{data_type} older than #{cutoff_date}"

      result = case data_type
               when 'audit_logs'
                 enforce_audit_log_retention(cutoff_date, action, account_id)
               when 'user_activity'
                 enforce_activity_retention(cutoff_date, action, account_id)
               when 'session_logs'
                 enforce_session_retention(cutoff_date, account_id)
               when 'email_logs'
                 enforce_email_log_retention(cutoff_date, account_id)
               when 'webhook_logs'
                 enforce_webhook_retention(cutoff_date, account_id)
               when 'api_request_logs'
                 enforce_api_log_retention(cutoff_date, account_id)
               when 'analytics_data'
                 enforce_analytics_retention(cutoff_date, action, account_id)
               when 'file_uploads'
                 enforce_file_retention(cutoff_date, account_id)
               else
                 { records_processed: 0 }
               end

      # Update policy with enforcement timestamp
      api_client.patch(
        "/api/v1/internal/data_retention_policies/#{policy['id']}",
        {
          last_enforced_at: Time.current.iso8601,
          records_processed_count: (policy['records_processed_count'] || 0) + result[:records_processed]
        }
      )

      result
    end

    def enforce_audit_log_retention(cutoff_date, action, account_id)
      case action
      when 'archive'
        archive_audit_logs(cutoff_date, account_id)
      when 'anonymize'
        anonymize_audit_logs(cutoff_date, account_id)
      when 'delete'
        # Audit logs should never be deleted, only archived
        archive_audit_logs(cutoff_date, account_id)
      end
    end

    def enforce_activity_retention(cutoff_date, action, account_id)
      case action
      when 'anonymize'
        response = api_client.patch(
          '/api/v1/internal/retention/activity/anonymize',
          { cutoff_date: cutoff_date, account_id: account_id }
        )
        { records_processed: response[:data]&.dig('count') || 0 }
      when 'delete'
        response = api_client.delete(
          '/api/v1/internal/retention/activity',
          { cutoff_date: cutoff_date, account_id: account_id }
        )
        { records_processed: response[:data]&.dig('count') || 0 }
      else
        { records_processed: 0 }
      end
    end

    def enforce_session_retention(cutoff_date, account_id)
      response = api_client.delete(
        '/api/v1/internal/retention/sessions',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def enforce_email_log_retention(cutoff_date, account_id)
      response = api_client.delete(
        '/api/v1/internal/retention/email_logs',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def enforce_webhook_retention(cutoff_date, account_id)
      response = api_client.delete(
        '/api/v1/internal/retention/webhook_logs',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def enforce_api_log_retention(cutoff_date, account_id)
      response = api_client.delete(
        '/api/v1/internal/retention/api_logs',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def enforce_analytics_retention(cutoff_date, action, account_id)
      case action
      when 'anonymize'
        response = api_client.patch(
          '/api/v1/internal/retention/analytics/anonymize',
          { cutoff_date: cutoff_date, account_id: account_id }
        )
        { records_processed: response[:data]&.dig('count') || 0 }
      when 'delete'
        response = api_client.delete(
          '/api/v1/internal/retention/analytics',
          { cutoff_date: cutoff_date, account_id: account_id }
        )
        { records_processed: response[:data]&.dig('count') || 0 }
      else
        { records_processed: 0 }
      end
    end

    def enforce_file_retention(cutoff_date, account_id)
      response = api_client.delete(
        '/api/v1/internal/retention/files',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def archive_audit_logs(cutoff_date, account_id)
      response = api_client.post(
        '/api/v1/internal/retention/audit_logs/archive',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end

    def anonymize_audit_logs(cutoff_date, account_id)
      response = api_client.patch(
        '/api/v1/internal/retention/audit_logs/anonymize',
        { cutoff_date: cutoff_date, account_id: account_id }
      )
      { records_processed: response[:data]&.dig('count') || 0 }
    end
  end
end
