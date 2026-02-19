# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Human Approval node executor - creates approval requests and pauses workflow
    #
    # Configuration:
    # - approvers: User IDs or role/group references
    # - approval_type: any, all, majority, quorum
    # - quorum_size: For quorum approval
    # - timeout: Auto-reject after timeout (seconds)
    # - timeout_action: reject, approve, escalate
    # - escalation_chain: Users to escalate to on timeout
    # - notification_channels: How to notify approvers
    # - context_data: Data to show approvers
    # - approval_form: Optional form for approvers to fill
    #
    class HumanApproval < Base
      include Concerns::WorkerDispatch

      APPROVAL_TYPES = %w[any all majority quorum].freeze
      TIMEOUT_ACTIONS = %w[reject approve escalate skip].freeze

      protected

      def perform_execution
        log_info "Executing human approval node"

        approvers = resolve_approvers(configuration["approvers"])
        approval_type = configuration["approval_type"] || "any"
        quorum_size = configuration["quorum_size"] || 1
        timeout = configuration["timeout"] || 86_400
        timeout_action = configuration["timeout_action"] || "reject"
        escalation_chain = configuration["escalation_chain"] || []
        notification_channels = configuration["notification_channels"] || ["email"]
        context_data = configuration["context_data"] || {}
        approval_form = configuration["approval_form"]
        instructions = resolve_value(configuration["instructions"])

        validate_configuration!(approvers, approval_type, timeout_action)

        required_approvals = calculate_required_approvals(approval_type, approvers, quorum_size)

        payload = {
          approvers: approvers,
          approval_type: approval_type,
          required_approvals: required_approvals,
          quorum_size: quorum_size,
          timeout: timeout,
          timeout_action: timeout_action,
          escalation_chain: escalation_chain,
          notification_channels: notification_channels,
          context_data: context_data,
          approval_form: approval_form,
          instructions: instructions,
          workflow_run_id: @orchestrator&.workflow_run&.id,
          node_id: @node.node_id
        }

        log_info "Dispatching approval request for #{approvers.length} approvers (type: #{approval_type})"

        dispatch_to_worker("Devops::ApprovalNotificationJob", payload, queue: "email")
      end

      private

      def validate_configuration!(approvers, approval_type, timeout_action)
        raise ArgumentError, "approvers is required" if approvers.blank?

        unless APPROVAL_TYPES.include?(approval_type)
          raise ArgumentError, "Invalid approval_type: #{approval_type}. Allowed: #{APPROVAL_TYPES.join(', ')}"
        end

        unless TIMEOUT_ACTIONS.include?(timeout_action)
          raise ArgumentError, "Invalid timeout_action: #{timeout_action}. Allowed: #{TIMEOUT_ACTIONS.join(', ')}"
        end
      end

      def calculate_required_approvals(approval_type, approvers, quorum_size)
        case approval_type
        when "any" then 1
        when "all" then approvers.length
        when "majority" then (approvers.length / 2.0).ceil
        when "quorum" then [quorum_size, approvers.length].min
        end
      end

      def resolve_approvers(approvers_config)
        return [] if approvers_config.blank?

        if approvers_config.is_a?(Array)
          approvers_config.map { |a| resolve_value(a) }.flatten.compact
        else
          resolved = resolve_value(approvers_config)
          resolved.is_a?(Array) ? resolved : [resolved]
        end.compact
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end
    end
  end
end
