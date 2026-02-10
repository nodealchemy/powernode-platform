# frozen_string_literal: true

module Api
  module V1
    module Ai
      class GovernanceController < ApplicationController
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

        # Approval Chains
        # GET /api/v1/ai/governance/approval_chains
        def approval_chains
          chains = current_account.ai_approval_chains
                                 .order(created_at: :desc)
                                 .page(params[:page])
                                 .per(params[:per_page] || 20)

          render_success(
            approval_chains: chains.map { |c| approval_chain_json(c) },
            pagination: pagination_meta(chains)
          )
        end

        # POST /api/v1/ai/governance/approval_chains
        def create_approval_chain
          chain = @service.create_approval_chain(
            name: params[:name],
            trigger_type: params[:trigger_type],
            steps: params[:steps] || [],
            user: current_user,
            description: params[:description],
            timeout_hours: params[:timeout_hours]
          )

          render_success(approval_chain: approval_chain_json(chain), status: :created)
        end

        # Approval Requests
        # GET /api/v1/ai/governance/approval_requests
        def approval_requests
          requests = current_account.ai_approval_requests
                                   .includes(:approval_chain)
                                   .order(created_at: :desc)
                                   .page(params[:page])
                                   .per(params[:per_page] || 20)

          requests = requests.where(status: params[:status]) if params[:status].present?

          render_success(
            approval_requests: requests.map { |r| approval_request_json(r) },
            pagination: pagination_meta(requests)
          )
        end

        # GET /api/v1/ai/governance/approval_requests/pending
        def pending_approvals
          requests = current_account.ai_approval_requests.active
                                   .includes(:approval_chain)
                                   .order(created_at: :desc)

          render_success(approval_requests: requests.map { |r| approval_request_json(r) })
        end

        # POST /api/v1/ai/governance/approval_requests/:id/decide
        def decide_approval
          request = current_account.ai_approval_requests.find(params[:id])
          result = @service.process_approval_decision(
            request: request,
            user: current_user,
            decision: params[:decision],
            comments: params[:comments],
            conditions: params[:conditions] || {}
          )

          if result[:success]
            render_success(approval_request: approval_request_json(result[:request]))
          else
            render_error(result[:error], :unprocessable_content)
          end
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

          render_success(
            entries: entries.map { |e| audit_entry_json(e) },
            pagination: pagination_meta(entries)
          )
        end

        private

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

        def approval_chain_json(chain)
          {
            id: chain.id,
            name: chain.name,
            description: chain.description,
            trigger_type: chain.trigger_type,
            trigger_conditions: chain.trigger_conditions,
            steps: chain.steps,
            status: chain.status,
            is_sequential: chain.is_sequential,
            timeout_hours: chain.timeout_hours,
            usage_count: chain.usage_count,
            created_at: chain.created_at
          }
        end

        def approval_request_json(request)
          {
            id: request.id,
            request_id: request.request_id,
            status: request.status,
            source_type: request.source_type,
            source_id: request.source_id,
            description: request.description,
            request_data: request.request_data,
            step_statuses: request.step_statuses,
            current_step: request.current_step,
            expires_at: request.expires_at,
            completed_at: request.completed_at,
            created_at: request.created_at,
            approval_chain: {
              id: request.approval_chain.id,
              name: request.approval_chain.name
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

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
