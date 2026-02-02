# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Human Approval node executor - creates approval requests and manages approval workflow
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
      APPROVAL_TYPES = %w[any all majority quorum].freeze
      TIMEOUT_ACTIONS = %w[reject approve escalate skip].freeze

      protected

      def perform_execution
        log_info "Executing human approval node"

        approvers = resolve_approvers(configuration["approvers"])
        approval_type = configuration["approval_type"] || "any"
        quorum_size = configuration["quorum_size"] || 1
        timeout = configuration["timeout"] || 86_400 # Default 24 hours
        timeout_action = configuration["timeout_action"] || "reject"
        escalation_chain = configuration["escalation_chain"] || []
        notification_channels = configuration["notification_channels"] || [ "email" ]
        context_data = configuration["context_data"] || {}
        approval_form = configuration["approval_form"]
        instructions = resolve_value(configuration["instructions"])

        validate_configuration!(approvers, approval_type, timeout_action)

        approval_context = {
          approvers: approvers,
          approval_type: approval_type,
          quorum_size: quorum_size,
          timeout: timeout,
          timeout_action: timeout_action,
          escalation_chain: escalation_chain,
          notification_channels: notification_channels,
          context_data: context_data,
          approval_form: approval_form,
          instructions: instructions,
          started_at: Time.current
        }

        log_info "Creating approval request for #{approvers.length} approvers (type: #{approval_type})"

        # Create approval request
        result = create_approval_request(approval_context)

        # Send notifications
        send_approval_notifications(approval_context, result[:approval_id])

        build_output(approval_context, result)
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

      def resolve_approvers(approvers_config)
        return [] if approvers_config.blank?

        # Resolve variables in approvers list
        if approvers_config.is_a?(Array)
          approvers_config.map { |a| resolve_value(a) }.flatten.compact
        else
          resolved = resolve_value(approvers_config)
          resolved.is_a?(Array) ? resolved : [ resolved ]
        end.compact
      end

      def create_approval_request(context)
        # Generate approval request ID
        approval_id = "apr_#{SecureRandom.hex(16)}"

        # Calculate required approvals based on type
        required_approvals = case context[:approval_type]
        when "any" then 1
        when "all" then context[:approvers].length
        when "majority" then (context[:approvers].length / 2.0).ceil
        when "quorum" then [ context[:quorum_size], context[:approvers].length ].min
        end

        # Calculate deadline
        deadline = Time.current + context[:timeout].seconds

        # NOTE: In production, this would:
        # 1. Create an ApprovalRequest record in the database
        # 2. Store workflow execution ID for resume
        # 3. Track individual approver responses

        {
          approval_id: approval_id,
          status: "pending",
          required_approvals: required_approvals,
          current_approvals: 0,
          current_rejections: 0,
          deadline: deadline.iso8601,
          approvers: context[:approvers].map do |approver|
            {
              id: approver,
              status: "pending",
              response: nil,
              responded_at: nil
            }
          end
        }
      end

      def send_approval_notifications(context, approval_id)
        # NOTE: In production, this would send actual notifications
        # via the configured channels (email, slack, etc.)

        context[:notification_channels].each do |channel|
          log_info "Sending #{channel} notification to #{context[:approvers].length} approvers"
        end

        {
          notifications_sent: context[:approvers].length * context[:notification_channels].length,
          channels_used: context[:notification_channels]
        }
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

      def build_output(context, result)
        {
          output: {
            approval_requested: true,
            approval_id: result[:approval_id],
            status: result[:status]
          },
          data: {
            approval_id: result[:approval_id],
            status: result[:status],
            approval_type: context[:approval_type],
            required_approvals: result[:required_approvals],
            current_approvals: result[:current_approvals],
            approvers_count: context[:approvers].length,
            deadline: result[:deadline],
            timeout_action: context[:timeout_action],
            has_form: context[:approval_form].present?,
            notification_channels: context[:notification_channels],
            created_at: Time.current.iso8601,
            workflow_paused: true
          },
          result: {
            approved: false,
            approval_status: "pending",
            approval_id: result[:approval_id],
            requires_action: true
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "human_approval",
            executed_at: Time.current.iso8601,
            workflow_state: "paused_for_approval"
          }
        }
      end
    end
  end
end
