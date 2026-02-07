# frozen_string_literal: true

module Ai
  class GovernanceService
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # Policy Management
    def create_policy(name:, policy_type:, enforcement_level:, conditions: {}, actions: {}, user: nil, description: nil, category: nil)
      Ai::CompliancePolicy.create!(
        account: account,
        created_by: user,
        name: name,
        policy_type: policy_type,
        enforcement_level: enforcement_level,
        conditions: conditions,
        actions: actions,
        description: description,
        category: category,
        status: "draft"
      )
    end

    def activate_policy(policy)
      policy.activate!
      { success: true, policy: policy }
    end

    def evaluate_policies(context, resource: nil)
      policies = account.ai_compliance_policies.active.ordered_by_priority

      results = []
      blocked = false

      policies.each do |policy|
        next if resource && !policy.applies_to?(resource)

        result = policy.evaluate(context)
        results << {
          policy: policy,
          allowed: result[:allowed],
          reason: result[:reason],
          enforcement: result[:enforcement]
        }

        if !result[:allowed] && policy.blocking?
          blocked = true
          break
        end
      end

      { allowed: !blocked, results: results }
    end

    # Approval Chains
    def create_approval_chain(name:, trigger_type:, steps:, user: nil, description: nil, timeout_hours: nil)
      Ai::ApprovalChain.create!(
        account: account,
        created_by: user,
        name: name,
        trigger_type: trigger_type,
        steps: steps,
        description: description,
        timeout_hours: timeout_hours,
        status: "active"
      )
    end

    def request_approval(chain:, source_type:, source_id:, description:, request_data: {}, user: nil)
      request = chain.create_request!(
        source_type: source_type,
        source_id: source_id,
        description: description,
        request_data: request_data,
        requested_by: user
      )

      # Notify approvers
      notify_approvers(request)

      { success: true, request: request }
    end

    def process_approval_decision(request:, user:, decision:, comments: nil, conditions: {})
      return { success: false, error: "Cannot approve" } unless request.can_approve?(user)

      request.record_decision!(
        approver: user,
        decision: decision,
        comments: comments,
        conditions: conditions
      )

      { success: true, request: request.reload }
    end

    def check_approval_required(trigger_type:, context: {})
      chains = account.ai_approval_chains.active.by_trigger(trigger_type)

      chains.find { |chain| chain.matches_trigger?(context) }
    end

    # Data Classification
    def create_classification(name:, level:, detection_patterns: [], handling_requirements: {}, user: nil)
      Ai::DataClassification.create!(
        account: account,
        classified_by: user,
        name: name,
        classification_level: level,
        detection_patterns: detection_patterns,
        handling_requirements: handling_requirements
      )
    end

    def scan_for_sensitive_data(text, source_type:, source_id:)
      classifications = account.ai_data_classifications.ordered_by_sensitivity
      detections = []

      classifications.each do |classification|
        matches = classification.detect_in_text(text)
        matches.each do |match|
          detection = classification.record_detection!(
            source_type: source_type,
            source_id: source_id,
            field_path: match[:position].to_s,
            original: match[:match],
            action: classification.requires_masking ? "masked" : "logged",
            confidence: 1.0
          )
          detections << detection
        end
      end

      { detections: detections, has_sensitive_data: detections.any? }
    end

    def mask_sensitive_data(text)
      classifications = account.ai_data_classifications.requiring_masking.ordered_by_sensitivity
      masked_text = text.dup

      classifications.each do |classification|
        matches = classification.detect_in_text(masked_text)
        matches.sort_by { |m| -m[:position] }.each do |match|
          masked_value = classification.mask_value(match[:match])
          masked_text[match[:position], match[:match].length] = masked_value
        end
      end

      masked_text
    end

    # Compliance Reports
    def generate_report(report_type:, period_start: nil, period_end: nil, config: {}, user: nil, format: "pdf")
      report = Ai::ComplianceReport.create!(
        account: account,
        generated_by: user,
        report_type: report_type,
        status: "generating",
        format: format,
        period_start: period_start,
        period_end: period_end,
        report_config: config
      )

      # Generate report asynchronously
      # Ai::GenerateComplianceReportJob.perform_async(report.id)

      report
    end

    def get_compliance_summary(start_date: 30.days.ago, end_date: Time.current)
      {
        policies: {
          total: account.ai_compliance_policies.count,
          active: account.ai_compliance_policies.active.count,
          by_type: account.ai_compliance_policies.group(:policy_type).count
        },
        violations: {
          total: account.ai_policy_violations.for_period(start_date, end_date).count,
          open: account.ai_policy_violations.open.count,
          by_severity: account.ai_policy_violations.for_period(start_date, end_date).group(:severity).count
        },
        approvals: {
          pending: account.ai_approval_requests.pending.count,
          approved: account.ai_approval_requests.approved.for_period(start_date, end_date).count,
          rejected: account.ai_approval_requests.rejected.for_period(start_date, end_date).count
        },
        data_detections: {
          total: account.ai_data_detections.for_period(start_date, end_date).count,
          by_action: account.ai_data_detections.for_period(start_date, end_date).group(:action_taken).count
        }
      }
    end

    # Audit Logging
    def log_audit_entry(action_type:, resource_type:, resource_id: nil, outcome:, user: nil, description: nil, before_state: {}, after_state: {}, context: {}, request: nil)
      Ai::ComplianceAuditEntry.log!(
        account: account,
        user: user,
        action_type: action_type,
        resource_type: resource_type,
        resource_id: resource_id,
        outcome: outcome,
        description: description,
        before_state: before_state,
        after_state: after_state,
        context: context,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent
      )
    end

    private

    def notify_approvers(request)
      step_info = request.current_step_info
      return unless step_info

      approvers = step_info["approvers"] || []
      return if approvers.empty?

      notification_data = {
        request_id: request.request_id,
        source_type: request.source_type,
        source_id: request.source_id,
        description: request.description,
        step_name: step_info["name"],
        approval_chain_name: request.approval_chain&.name,
        requested_by: request.requested_by&.name,
        timeout_at: request.timeout_at&.iso8601
      }

      approvers.each do |approver_id|
        user = User.find_by(id: approver_id)
        next unless user

        # Send in-app notification
        NotificationService.send_all(
          template: "ai_governance_approval_requested",
          message: "AI governance approval requested: #{request.description&.truncate(100)}",
          user_id: user.id,
          notification_type: "action_required",
          account_id: account.id,
          data: notification_data
        )
      end

      # Broadcast to AI Workflow channel for real-time updates
      AiWorkflowOrchestrationChannel.broadcast_approval_requested(
        account,
        request_id: request.id,
        step_name: step_info["name"],
        approvers: approvers
      )

      Rails.logger.info "Approval requested for #{request.request_id}, notified #{approvers.length} approvers"
    end
  end
end
