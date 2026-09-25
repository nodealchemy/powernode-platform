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
          policies violations classifications
          reports summary audit_log security_events
        ].freeze

        WRITE_ACTIONS = %i[
          create_policy activate_policy toggle_policy evaluate_policies
          acknowledge_violation resolve_violation
          create_classification scan_data mask_data
          generate_report
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

        # PUT /api/v1/ai/governance/policies/:id/activate
        def activate_policy
          policy = current_account.ai_compliance_policies.find(params[:id])
          result = @service.activate_policy(policy)

          render_success(policy: policy_json(result[:policy]))
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

        # POST /api/v1/ai/governance/policies/evaluate
        def evaluate_policies
          result = @service.evaluate_policies(params[:context] || {})

          render_success(
            allowed: result[:allowed],
            results: result[:results].map { |r| evaluation_result_json(r) }
          )
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

        # PUT /api/v1/ai/governance/violations/:id/acknowledge
        def acknowledge_violation
          violation = current_account.ai_policy_violations.find(params[:id])
          violation.acknowledge!(current_user)

          render_success(violation: violation_json(violation))
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

        # Data Classifications
        # GET /api/v1/ai/governance/classifications
        def classifications
          classifications = current_account.ai_data_classifications
                                          .ordered_by_sensitivity
                                          .page(params[:page])
                                          .per(params[:per_page] || 20)

          render_success(
            classifications: classifications.map { |c| classification_json(c) },
            pagination: pagination_meta(classifications)
          )
        end

        # POST /api/v1/ai/governance/classifications
        def create_classification
          classification = @service.create_classification(
            name: params[:name],
            level: params[:classification_level],
            detection_patterns: params[:detection_patterns] || [],
            handling_requirements: params[:handling_requirements] || {},
            user: current_user
          )

          render_success(classification: classification_json(classification), status: :created)
        end

        # POST /api/v1/ai/governance/scan
        def scan_data
          result = @service.scan_for_sensitive_data(
            params[:text],
            source_type: params[:source_type],
            source_id: params[:source_id]
          )

          render_success(
            has_sensitive_data: result[:has_sensitive_data],
            detections: result[:detections].map { |d| detection_json(d) }
          )
        end

        # POST /api/v1/ai/governance/mask
        def mask_data
          masked_text = @service.mask_sensitive_data(params[:text])
          render_success(masked_text: masked_text)
        end

        # Reports
        # GET /api/v1/ai/governance/reports
        def reports
          reports = current_account.ai_compliance_reports
                                  .recent
                                  .page(params[:page])
                                  .per(params[:per_page] || 20)

          render_success(
            reports: reports.map { |r| report_json(r) },
            pagination: pagination_meta(reports)
          )
        end

        # POST /api/v1/ai/governance/reports
        def generate_report
          report = @service.generate_report(
            report_type: params[:report_type],
            period_start: params[:period_start]&.to_datetime,
            period_end: params[:period_end]&.to_datetime,
            config: params[:config] || {},
            user: current_user
          )

          render_success(report: report_json(report), status: :created)
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

        def evaluation_result_json(result)
          {
            policy_id: result[:policy].id,
            policy_name: result[:policy].name,
            allowed: result[:allowed],
            reason: result[:reason],
            enforcement: result[:enforcement]
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

        def classification_json(classification)
          {
            id: classification.id,
            name: classification.name,
            classification_level: classification.classification_level,
            description: classification.description,
            detection_patterns: classification.detection_patterns,
            handling_requirements: classification.handling_requirements,
            requires_encryption: classification.requires_encryption,
            requires_masking: classification.requires_masking,
            requires_audit: classification.requires_audit,
            is_system: classification.is_system,
            detection_count: classification.detection_count
          }
        end

        def detection_json(detection)
          {
            id: detection.id,
            detection_id: detection.detection_id,
            classification_level: detection.classification_level,
            source_type: detection.source_type,
            field_path: detection.field_path,
            action_taken: detection.action_taken,
            masked_snippet: detection.masked_snippet,
            confidence_score: detection.confidence_score,
            created_at: detection.created_at
          }
        end

        def report_json(report)
          {
            id: report.id,
            report_id: report.report_id,
            report_type: report.report_type,
            status: report.status,
            format: report.format,
            period_start: report.period_start,
            period_end: report.period_end,
            summary_data: report.summary_data,
            file_path: report.file_path,
            file_size_bytes: report.file_size_bytes,
            generated_at: report.generated_at,
            expires_at: report.expires_at
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
