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
        # Hook for the pending operator decision on system-wide policies.
        # Nothing emits `scope` today: there is no column and the index does
        # not return it, so in practice every nil-account policy is refused.
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

      base[:scope] = scope[:scope]

      # A nil/blank/non-numeric value would become 0 days, a cutoff of "now",
      # and purge every row: refuse it before any call.
      retention_days = Integer(policy['retention_days'].to_s, 10, exception: false)
      if retention_days.nil? || retention_days < 1
        log_warn "Refusing retention policy #{policy['id']} (#{data_type}): invalid retention_days " \
                 "#{policy['retention_days'].inspect}"
        return base.merge(status: 'skipped_invalid', records_processed: 0)
      end

      params = { cutoff_date: retention_days.days.ago.iso8601 }.merge(scope)
      log_info "Enforcing #{action} for #{data_type} older than #{params[:cutoff_date]} (#{scope[:scope]} scope)"

      count = run_purge(data_type, action, params, base)
      return base.merge(status: 'unsupported', records_processed: 0) if count.nil?

      record_enforcement(policy, count)
      base.merge(status: 'enforced', records_processed: count)
    rescue UnroutedError => e
      log_error "Retention purge unrouted for policy #{policy['id']}: #{e.message}"
      base.merge(status: 'unrouted', records_processed: 0, error: e.message)
    rescue StandardError => e
      log_error "Failed to enforce policy #{policy['id']}: #{e.message}"
      base.merge(status: 'failed', records_processed: 0, error: e.message)
    end

    # One explicit client call per row, the verb and the full literal path on the same line, so
    # spec/support/worker_route_census.rb reads both. Returns the purged count, or nil when the
    # data type + action has nothing to call. Each row names the call it makes: base[:call] records
    # what actually ran (an audit_logs delete runs archive).
    def run_purge(data_type, action, params, base)
      case data_type
      when 'audit_logs'
        # Audit logs are never deleted, only archived
        if action == 'anonymize'
          purge(base, 'PATCH audit_logs/anonymize') { api_client.patch("/api/v1/internal/retention/audit_logs/anonymize", params) }
        else
          purge(base, 'POST audit_logs/archive') { api_client.post("/api/v1/internal/retention/audit_logs/archive", params) }
        end
      when 'user_activity'
        case action
        when 'anonymize' then purge(base, 'PATCH activity/anonymize') { api_client.patch("/api/v1/internal/retention/activity/anonymize", params) }
        when 'delete' then purge(base, 'DELETE activity') { api_client.delete("/api/v1/internal/retention/activity", params) }
        end
      when 'analytics_data'
        case action
        when 'anonymize' then purge(base, 'PATCH analytics/anonymize') { api_client.patch("/api/v1/internal/retention/analytics/anonymize", params) }
        when 'delete' then purge(base, 'DELETE analytics') { api_client.delete("/api/v1/internal/retention/analytics", params) }
        end
      when 'session_logs' then purge(base, 'DELETE sessions') { api_client.delete("/api/v1/internal/retention/sessions", params) }
      when 'email_logs' then purge(base, 'DELETE email_logs') { api_client.delete("/api/v1/internal/retention/email_logs", params) }
      when 'webhook_logs' then purge(base, 'DELETE webhook_logs') { api_client.delete("/api/v1/internal/retention/webhook_logs", params) }
      when 'api_request_logs' then purge(base, 'DELETE api_logs') { api_client.delete("/api/v1/internal/retention/api_logs", params) }
      when 'file_uploads' then purge(base, 'DELETE files') { api_client.delete("/api/v1/internal/retention/files", params) }
      end
    end

    def purge(base, call)
      base[:call] = call
      response = guard_unrouted(call) { yield }
      raise "#{call} returned success=false: #{response&.dig('error')}" unless response&.dig('success')

      response.dig('data', 'count') || 0
    end

    # Bookkeeping only: a failure here does not undo the purge, but an
    # unrouted PATCH is still counted so the audit stays truthful.
    def record_enforcement(policy, count)
      guard_unrouted('PATCH data_retention_policies') do
        api_client.patch("/api/v1/internal/data_retention_policies/#{policy['id']}", {
                           last_enforced_at: Time.current.iso8601,
                           records_processed_count: (policy['records_processed_count'] || 0) + count
                         })
      end
    rescue StandardError => e
      log_warn "Could not record enforcement for policy #{policy['id']}: #{e.message}"
    end

    # Runs the block's client call; a 404 is counted and re-raised as UnroutedError.
    def guard_unrouted(call)
      yield
    rescue BackendApiClient::ApiError => e
      raise unless e.status == 404

      @unrouted_calls += 1
      raise UnroutedError, "#{call} has no route"
    end

    def summarize(policy_results)
      total = policy_results.size
      enforced = policy_results.count { |r| r[:status] == 'enforced' }
      records = policy_results.sum { |r| r[:records_processed] }
      unrouted = @unrouted_calls
      unscoped = policy_results.count { |r| r[:status] == 'skipped_unscoped' }
      invalid = policy_results.count { |r| r[:status] == 'skipped_invalid' }
      refused = unscoped + invalid

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
      summary += ", #{refused} refused (#{unscoped} unscoped, #{invalid} invalid)" if refused.positive?

      {
        outcome: outcome,
        summary: summary,
        policies_total: total,
        policies_processed: enforced,
        records_processed: records,
        unrouted_calls: unrouted,
        policies_refused: refused,
        policy_results: policy_results,
        errors: policy_results.select { |r| r[:error] }.map { |r| { policy_id: r[:policy_id], error: r[:error] } }
      }
    end
  end
end
