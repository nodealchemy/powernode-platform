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

    # Approval Chains
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

    def check_approval_required(trigger_type:, context: {})
      chains = account.ai_approval_chains.active.by_trigger(trigger_type)

      chains.find { |chain| chain.matches_trigger?(context) }
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

      Rails.logger.info "Approval requested for #{request.request_id}, notified #{approvers.length} approvers"
    end
  end
end
