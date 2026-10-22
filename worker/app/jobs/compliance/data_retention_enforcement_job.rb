# frozen_string_literal: true

module Compliance
  # Daily job for enforcing data retention policies
  # Runs at 2 AM daily to process expired data
  #
  # PENDING OPERATOR DECISION (IMP-01a163fa): only the policy index
  # (GET /api/v1/internal/data_retention_policies) is routed. The purge
  # endpoints under /api/v1/internal/retention/* and the PATCH that records
  # enforcement have no route, and no policies are seeded
  # (RetentionPolicy.ensure_defaults! is never called). Restoring those routes
  # and seeding defaults are operator decisions, deliberately not made here.
  # Until then this job reports "retention not configured" or
  # "retention enforcement failed: N calls unrouted" in its nightly audit.
  #
  # Tenant scope: a policy acts only on its own account_id. A policy with no
  # account_id is refused unless it says scope: "system" explicitly; a nil
  # account_id is never read as system-wide.
  class DataRetentionEnforcementJob < BaseJob
    sidekiq_options queue: :compliance

    RETENTION_PATH = '/api/v1/internal/retention'

    # Raised when a purge call reaches no route (404), so the audit can tell
    # "unrouted" apart from other failures.
    class UnroutedError < StandardError; end

    def execute(_args = nil)
      log_info 'Starting data retention enforcement'

      # Fetch active retention policies
      response = api_client.get('/api/v1/internal/data_retention_policies', { active: true })

      unless response["success"]
        raise "Failed to fetch retention policies: #{response["error"]}"
      end

      policies = response["data"] || []
      @unrouted_calls = 0
      policy_results = policies.map { |policy| enforce_policy(policy) }

      results = summarize(policy_results)
      log_info "Data retention enforcement: #{results[:summary]}"

      api_client.post(
        '/api/v1/internal/audit_logs',
        {
          action: 'compliance_check',
          resource_type: 'DataRetentionPolicy',
          resource_id: 'enforcement_job',
          source: 'worker',
          severity: results[:outcome] == 'enforced' ? 'low' : 'medium',
          metadata: results
        }
      )

      results
    end

    private

    # Returns the scope params every purge call carries, or nil when the policy
    # has no explicit scope and must be refused.
    def purge_scope(policy)
      account_id = policy['account_id'].to_s.strip
      declared = policy['scope']

      if account_id.present?
        return nil if declared.present? && declared != 'account'

        { scope: 'account', account_id: account_id }
      elsif declared == 'system'
        { scope: 'system' }
      end
    end

    def enforce_policy(policy)
      data_type = policy['data_type']
      action = policy['action']
      base = { policy_id: policy['id'], data_type: data_type, action: action, account_id: policy['account_id'] }

      scope = purge_scope(policy)
      unless scope
        log_warn "Refusing retention policy #{policy['id']} (#{data_type}): no explicit scope " \
                 "(account_id=#{policy['account_id'].inspect}, scope=#{policy['scope'].inspect})"
        return base.merge(status: 'skipped_unscoped', records_processed: 0)
      end

      params = { cutoff_date: policy['retention_days'].to_i.days.ago.iso8601 }.merge(scope)
      log_info "Enforcing #{action} for #{data_type} older than #{params[:cutoff_date]} (#{scope[:scope]} scope)"

      call = purge_call(data_type, action)
      return base.merge(scope: scope[:scope], status: 'unsupported', records_processed: 0) unless call

      count = purge(*call, params)
      record_enforcement(policy, count)
      base.merge(scope: scope[:scope], status: 'enforced', records_processed: count)
    rescue UnroutedError => e
      log_error "Retention purge unrouted for policy #{policy['id']}: #{e.message}"
      base.merge(scope: scope&.dig(:scope), status: 'unrouted', records_processed: 0, error: e.message)
    rescue StandardError => e
      log_error "Failed to enforce policy #{policy['id']}: #{e.message}"
      base.merge(scope: scope&.dig(:scope), status: 'failed', records_processed: 0, error: e.message)
    end

    # [verb, path] for a data type + action, or nil when there is nothing to call.
    def purge_call(data_type, action)
      case data_type
      when 'audit_logs'
        # Audit logs are never deleted, only archived
        action == 'anonymize' ? [:patch, 'audit_logs/anonymize'] : [:post, 'audit_logs/archive']
      when 'user_activity'
        { 'anonymize' => [:patch, 'activity/anonymize'], 'delete' => [:delete, 'activity'] }[action]
      when 'analytics_data'
        { 'anonymize' => [:patch, 'analytics/anonymize'], 'delete' => [:delete, 'analytics'] }[action]
      when 'session_logs' then [:delete, 'sessions']
      when 'email_logs' then [:delete, 'email_logs']
      when 'webhook_logs' then [:delete, 'webhook_logs']
      when 'api_request_logs' then [:delete, 'api_logs']
      when 'file_uploads' then [:delete, 'files']
      end
    end

    def purge(verb, path, params)
      response = call_api(verb, "#{RETENTION_PATH}/#{path}", params)
      raise "#{verb.upcase} #{path} returned success=false: #{response&.dig('error')}" unless response&.dig('success')

      response.dig('data', 'count') || 0
    end

    # Bookkeeping only: a failure here does not undo the purge, but an
    # unrouted PATCH is still counted so the audit stays truthful.
    def record_enforcement(policy, count)
      call_api(
        :patch,
        "/api/v1/internal/data_retention_policies/#{policy['id']}",
        {
          last_enforced_at: Time.current.iso8601,
          records_processed_count: (policy['records_processed_count'] || 0) + count
        }
      )
    rescue StandardError => e
      log_warn "Could not record enforcement for policy #{policy['id']}: #{e.message}"
    end

    def call_api(verb, path, params)
      api_client.public_send(verb, path, params)
    rescue BackendApiClient::ApiError => e
      raise unless e.status == 404

      @unrouted_calls += 1
      raise UnroutedError, "#{verb.upcase} #{path} has no route"
    end

    def summarize(policy_results)
      total = policy_results.size
      enforced = policy_results.count { |r| r[:status] == 'enforced' }
      records = policy_results.sum { |r| r[:records_processed] }
      unrouted = @unrouted_calls

      outcome, summary =
        if total.zero?
          ['not_configured', 'retention not configured']
        elsif enforced.zero?
          ['failed', unrouted.positive? ? "retention enforcement failed: #{unrouted} calls unrouted" :
                                          "retention enforcement failed: 0 of #{total} policies enforced"]
        elsif enforced < total
          ['partial', "retention enforcement partial: #{enforced} of #{total} policies enforced, " \
                      "#{unrouted} calls unrouted"]
        else
          ['enforced', "retention enforced: #{enforced} policies, #{records} records" \
                       "#{", #{unrouted} calls unrouted" if unrouted.positive?}"]
        end

      {
        outcome: outcome,
        summary: summary,
        policies_total: total,
        policies_processed: enforced,
        records_processed: records,
        unrouted_calls: unrouted,
        policy_results: policy_results,
        errors: policy_results.select { |r| r[:error] }.map { |r| { policy_id: r[:policy_id], error: r[:error] } }
      }
    end
  end
end
