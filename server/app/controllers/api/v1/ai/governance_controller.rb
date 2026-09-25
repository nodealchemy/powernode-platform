# frozen_string_literal: true

module Api
  module V1
    module Ai
      class GovernanceController < ApplicationController
        include Paginatable
        include AuditLogging
        # Authorization on the dedicated ai.governance.* family: reads gate on
        # `ai.governance.read`, writes on `ai.governance.manage` (both catalog-
        # defined). Decoupled from the coarse `ai.manage` gate so AI-operator
        # tokens without governance authority cannot mutate governance state.
        READ_ACTIONS = %i[
          policies violations summary audit_log security_events
        ].freeze

        WRITE_ACTIONS = %i[
          create_policy toggle_policy resolve_violation
        ].freeze

        before_action :require_governance_read, only: READ_ACTIONS
        before_action :require_governance_manage, only: WRITE_ACTIONS
        before_action :set_service

        # Policies
        # GET /api/v1/ai/governance/policies
        def policies
          policies = current_account.ai_compliance_policies
                                    .order(priority: :desc, created_at: :desc)
                                    .page(params[:page])
                                    .per(params[:per_page] || 20)

          policies = policies.where(policy_type: params[:type]) if params[:type].present?
          policies = policies.where(status: params[:status]) if params[:status].present?

          render_success(
            policies: policies.map { |p| policy_json(p) },
            pagination: pagination_meta(policies)
          )
        end

        # POST /api/v1/ai/governance/policies
        def create_policy
          policy = @service.create_policy(
            name: params[:name],
            policy_type: params[:policy_type],
            enforcement_level: params[:enforcement_level],
            conditions: params[:conditions] || {},
            actions: params[:actions] || {},
            user: current_user,
            description: params[:description],
            category: params[:category]
          )

          render_success(policy: policy_json(policy), status: :created)
        end

        # PUT /api/v1/ai/governance/policies/:id/toggle
        # An active policy is disabled; a draft or disabled one is activated.
        # Archived policies stay archived, and a required policy is never
        # switched off. Every change is a policy change, so it is audited.
        def toggle_policy
          policy = current_account.ai_compliance_policies.find(params[:id])
          old_status = policy.status

          if policy.status == "archived"
            return render_error("Archived policies cannot be toggled", status: :unprocessable_content)
          end
          if policy.active? && policy.is_required
            return render_error("Required policies cannot be disabled", status: :unprocessable_content)
          end

          policy.active? ? policy.deactivate! : policy.activate!
          log_audit_event("update", policy,
                          old_values: { status: old_status },
                          new_values: { status: policy.status },
                          metadata: { change: "compliance_policy_toggled" })

          render_success(policy: policy_json(policy))
        end

        # Violations
        # GET /api/v1/ai/governance/violations
        def violations
          violations = current_account.ai_policy_violations
                                     .includes(:policy)
                                     .recent
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

          violations = violations.where(status: params[:status]) if params[:status].present?
          violations = violations.where(severity: params[:severity]) if params[:severity].present?

          render_success(
            violations: violations.map { |v| violation_json(v) },
            pagination: pagination_meta(violations)
          )
        end

        # PUT /api/v1/ai/governance/violations/:id/resolve
        def resolve_violation
          violation = current_account.ai_policy_violations.find(params[:id])
          violation.resolve!(
            user: current_user,
            notes: params[:notes],
            action: params[:action]
          )

          render_success(violation: violation_json(violation))
        end

        # GET /api/v1/ai/governance/summary
        def summary
          summary = @service.get_compliance_summary(
            start_date: params[:start_date]&.to_datetime || 30.days.ago,
            end_date: params[:end_date]&.to_datetime || Time.current
          )

          render_success(summary: summary)
        end

        # Audit Log
        # GET /api/v1/ai/governance/audit_log
        def audit_log
          entries = current_account.ai_compliance_audit_entries
                                  .recent
                                  .page(params[:page])
                                  .per(params[:per_page] || 50)

          entries = entries.by_action(params[:action_type]) if params[:action_type].present?
          entries = entries.by_resource(params[:resource_type]) if params[:resource_type].present?

          start_date = parse_date_param(:start_date)
          end_date = parse_date_param(:end_date)
          return if performed?

          entries = entries.where(occurred_at: start_date.beginning_of_day..) if start_date
          entries = entries.where(occurred_at: ..end_date.end_of_day) if end_date

          render_success(
            entries: entries.map { |e| audit_entry_json(e) },
            pagination: pagination_meta(entries)
          )
        end

        # Security events: the account's security-relevant audit entries
        # (failed logins, 2FA changes, denied API access, ...).
        # GET /api/v1/ai/governance/security_events
        def security_events
          per_page = params[:per_page].to_i
          per_page = SECURITY_EVENTS_PER_PAGE if per_page < 1
          events = current_account.audit_logs
                                  .security_events
                                  .order(created_at: :desc)
                                  .page(params[:page])
                                  .per([ per_page, SECURITY_EVENTS_MAX_PER_PAGE ].min)

          %i[severity risk_level].each do |field|
            value = params[field]
            next if value.blank?
            unless SECURITY_EVENT_LEVELS.include?(value)
              return render_error("Invalid #{field}: must be one of #{SECURITY_EVENT_LEVELS.join(', ')}",
                                  status: :unprocessable_content)
            end

            events = events.where(field => value)
          end

          render_success(
            events: events.map { |e| security_event_json(e) },
            pagination: pagination_meta(events)
          )
        end

        private

        SECURITY_EVENTS_PER_PAGE = 50
        SECURITY_EVENTS_MAX_PER_PAGE = 100
        # AuditLog validates severity and risk_level against this same set.
        SECURITY_EVENT_LEVELS = %w[low medium high critical].freeze

        # A YYYY-MM-DD date param, or nil when absent. An unparseable date is
        # refused (422) rather than silently ignored, so a filter the operator
        # set never quietly widens to "everything".
        def parse_date_param(key)
          raw = params[key]
          return nil if raw.blank?

          Date.iso8601(raw.to_s)
        rescue Date::Error
          render_error("Invalid #{key}: expected YYYY-MM-DD", status: :unprocessable_content)
          nil
        end

        def security_event_json(entry)
          {
            id: entry.id,
            action: entry.action,
            resource_type: entry.resource_type,
            severity: entry.severity,
            risk_level: entry.risk_level,
            source: entry.source,
            ip_address: entry.ip_address,
            created_at: entry.created_at.iso8601
          }
        end

        def require_governance_read
          require_permission("ai.governance.read")
        end

        def require_governance_manage
          require_permission("ai.governance.manage")
        end

        def set_service
          @service = ::Ai::GovernanceService.new(current_account)
        end

        def policy_json(policy)
          {
            id: policy.id,
            name: policy.name,
            policy_type: policy.policy_type,
            category: policy.category,
            description: policy.description,
            status: policy.status,
            enforcement_level: policy.enforcement_level,
            conditions: policy.conditions,
            actions: policy.actions,
            is_system: policy.is_system,
            is_required: policy.is_required,
            priority: policy.priority,
            violation_count: policy.violation_count,
            last_triggered_at: policy.last_triggered_at,
            created_at: policy.created_at
          }
        end

        def violation_json(violation)
          {
            id: violation.id,
            violation_id: violation.violation_id,
            severity: violation.severity,
            status: violation.status,
            description: violation.description,
            context: violation.context,
            source_type: violation.source_type,
            source_id: violation.source_id,
            remediation_steps: violation.remediation_steps,
            resolution_notes: violation.resolution_notes,
            detected_at: violation.detected_at,
            resolved_at: violation.resolved_at,
            policy: {
              id: violation.policy.id,
              name: violation.policy.name
            }
          }
        end

        def audit_entry_json(entry)
          {
            id: entry.id,
            entry_id: entry.entry_id,
            action_type: entry.action_type,
            resource_type: entry.resource_type,
            resource_id: entry.resource_id,
            outcome: entry.outcome,
            description: entry.description,
            ip_address: entry.ip_address,
            occurred_at: entry.occurred_at,
            user_id: entry.user_id
          }
        end

      end
    end
  end
end
