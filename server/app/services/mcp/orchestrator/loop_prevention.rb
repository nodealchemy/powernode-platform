# frozen_string_literal: true

module Mcp
  module Orchestrator
    # LoopPrevention - Protects against endless loops in workflow execution
    #
    # Tracks and enforces limits on:
    # - Node visit counts (prevents feedback loops)
    # - Consecutive validation failures (prevents retry loops)
    # - Sub-workflow depth (prevents recursive workflows)
    # - Total node executions (ultimate safeguard)
    # - Node requeue counts (prevents deadlocks)
    #
    module LoopPrevention
      class LoopLimitExceededError < StandardError
        attr_reader :limit_type, :limit_value, :current_value, :node_id

        def initialize(message, limit_type:, limit_value:, current_value:, node_id: nil)
          @limit_type = limit_type
          @limit_value = limit_value
          @current_value = current_value
          @node_id = node_id
          super(message)
        end
      end

      # Default limits if not configured in workflow
      DEFAULT_LIMITS = {
        max_node_visits: 10,
        max_validation_failures: 5,
        max_sub_workflow_depth: 5,
        max_requeues_per_node: 100,
        max_total_node_executions: 1000,
        warn_on_approach: true
      }.freeze

      # Node types considered as validation/quality check nodes
      VALIDATION_NODE_TYPES = %w[validator condition].freeze

      def initialize_loop_prevention
        @loop_prevention_state = {
          node_visit_counts: Hash.new(0),
          validation_failure_counts: Hash.new(0),
          consecutive_validation_failures: 0,
          total_node_executions: 0,
          sub_workflow_depth: extract_sub_workflow_depth,
          requeue_counts: Hash.new(0),
          warnings_issued: Set.new
        }

        @logger.info "[LOOP_PREVENTION] Initialized with depth=#{@loop_prevention_state[:sub_workflow_depth]}"
      end

      def loop_prevention_limits
        @loop_prevention_limits ||= begin
          config = @workflow.configuration&.dig("loop_prevention") || {}
          DEFAULT_LIMITS.merge(config.symbolize_keys)
        end
      end

      # Called before executing any node
      def check_loop_prevention_before_execute(node)
        state = @loop_prevention_state

        # Check total executions
        check_total_executions_limit(state)

        # Check node visit count
        check_node_visit_limit(node, state)

        # Increment counters
        state[:node_visit_counts][node.node_id] += 1
        state[:total_node_executions] += 1

        # Log if approaching limits
        warn_approaching_limits(node, state) if loop_prevention_limits[:warn_on_approach]
      end

      # Called after a node execution completes
      def update_loop_prevention_after_execute(node, result)
        state = @loop_prevention_state

        if validation_node?(node)
          if result[:success] == false || result.dig(:output, :valid) == false
            # Validation failed
            state[:consecutive_validation_failures] += 1
            state[:validation_failure_counts][node.node_id] += 1

            check_consecutive_validation_failures(node, state)
          else
            # Validation passed - reset consecutive counter
            state[:consecutive_validation_failures] = 0
          end
        end
      end

      # Called when a node is requeued (waiting for prerequisites)
      def check_requeue_limit(node)
        state = @loop_prevention_state
        state[:requeue_counts][node.node_id] += 1

        max_requeues = loop_prevention_limits[:max_requeues_per_node]

        if state[:requeue_counts][node.node_id] > max_requeues
          raise LoopLimitExceededError.new(
            "Node '#{node.node_id}' requeued #{state[:requeue_counts][node.node_id]} times " \
            "(limit: #{max_requeues}). Prerequisites never satisfied - possible deadlock.",
            limit_type: :max_requeues_per_node,
            limit_value: max_requeues,
            current_value: state[:requeue_counts][node.node_id],
            node_id: node.node_id
          )
        end
      end

      # Check sub-workflow depth before executing a sub-workflow
      def check_sub_workflow_depth
        current_depth = @loop_prevention_state[:sub_workflow_depth]
        max_depth = loop_prevention_limits[:max_sub_workflow_depth]

        if current_depth >= max_depth
          raise LoopLimitExceededError.new(
            "Sub-workflow depth #{current_depth} exceeds maximum (#{max_depth}). " \
            "Possible recursive workflow call detected.",
            limit_type: :max_sub_workflow_depth,
            limit_value: max_depth,
            current_value: current_depth
          )
        end

        current_depth + 1
      end

      # Get loop prevention stats for monitoring
      def loop_prevention_stats
        state = @loop_prevention_state
        limits = loop_prevention_limits

        {
          total_node_executions: state[:total_node_executions],
          total_executions_limit: limits[:max_total_node_executions],
          total_executions_percentage: (state[:total_node_executions].to_f / limits[:max_total_node_executions] * 100).round(1),
          consecutive_validation_failures: state[:consecutive_validation_failures],
          validation_failures_limit: limits[:max_validation_failures],
          sub_workflow_depth: state[:sub_workflow_depth],
          sub_workflow_depth_limit: limits[:max_sub_workflow_depth],
          most_visited_nodes: state[:node_visit_counts].sort_by { |_, v| -v }.first(5).to_h,
          node_visit_limit: limits[:max_node_visits],
          warnings_issued: state[:warnings_issued].to_a
        }
      end

      private

      def check_total_executions_limit(state)
        max_total = loop_prevention_limits[:max_total_node_executions]

        if state[:total_node_executions] >= max_total
          raise LoopLimitExceededError.new(
            "Total node executions (#{state[:total_node_executions]}) reached maximum (#{max_total}). " \
            "Workflow may be stuck in an endless loop.",
            limit_type: :max_total_node_executions,
            limit_value: max_total,
            current_value: state[:total_node_executions]
          )
        end
      end

      def check_node_visit_limit(node, state)
        max_visits = loop_prevention_limits[:max_node_visits]
        current_visits = state[:node_visit_counts][node.node_id]

        if current_visits >= max_visits
          raise LoopLimitExceededError.new(
            "Node '#{node.node_id}' (#{node.name}) visited #{current_visits} times (limit: #{max_visits}). " \
            "Feedback loop detected - node is being revisited too many times.",
            limit_type: :max_node_visits,
            limit_value: max_visits,
            current_value: current_visits,
            node_id: node.node_id
          )
        end
      end

      def check_consecutive_validation_failures(node, state)
        max_failures = loop_prevention_limits[:max_validation_failures]

        if state[:consecutive_validation_failures] >= max_failures
          raise LoopLimitExceededError.new(
            "#{state[:consecutive_validation_failures]} consecutive validation failures " \
            "(limit: #{max_failures}). Quality check keeps failing - aborting to prevent endless retry loop.",
            limit_type: :max_validation_failures,
            limit_value: max_failures,
            current_value: state[:consecutive_validation_failures],
            node_id: node.node_id
          )
        end
      end

      def validation_node?(node)
        VALIDATION_NODE_TYPES.include?(node.node_type)
      end

      def warn_approaching_limits(node, state)
        limits = loop_prevention_limits
        warning_threshold = 0.8 # 80% of limit

        # Check node visits approaching limit
        node_visits = state[:node_visit_counts][node.node_id]
        max_visits = limits[:max_node_visits]
        if node_visits >= (max_visits * warning_threshold).floor && !state[:warnings_issued].include?("node_visits:#{node.node_id}")
          @logger.warn "[LOOP_PREVENTION] Warning: Node '#{node.node_id}' has been visited #{node_visits}/#{max_visits} times"
          state[:warnings_issued] << "node_visits:#{node.node_id}"

          @event_store&.record_event(
            event_type: "workflow.loop_prevention.warning",
            event_data: {
              warning_type: "node_visits_approaching_limit",
              node_id: node.node_id,
              current_value: node_visits,
              limit: max_visits
            }
          )
        end

        # Check total executions approaching limit
        total = state[:total_node_executions]
        max_total = limits[:max_total_node_executions]
        if total >= (max_total * warning_threshold).floor && !state[:warnings_issued].include?("total_executions")
          @logger.warn "[LOOP_PREVENTION] Warning: Total node executions at #{total}/#{max_total}"
          state[:warnings_issued] << "total_executions"

          @event_store&.record_event(
            event_type: "workflow.loop_prevention.warning",
            event_data: {
              warning_type: "total_executions_approaching_limit",
              current_value: total,
              limit: max_total
            }
          )
        end

        # Check validation failures approaching limit
        failures = state[:consecutive_validation_failures]
        max_failures = limits[:max_validation_failures]
        if failures >= (max_failures * warning_threshold).floor && !state[:warnings_issued].include?("validation_failures")
          @logger.warn "[LOOP_PREVENTION] Warning: #{failures} consecutive validation failures (limit: #{max_failures})"
          state[:warnings_issued] << "validation_failures"

          @event_store&.record_event(
            event_type: "workflow.loop_prevention.warning",
            event_data: {
              warning_type: "validation_failures_approaching_limit",
              current_value: failures,
              limit: max_failures
            }
          )
        end
      end

      def extract_sub_workflow_depth
        # Extract depth from parent workflow run context if this is a sub-workflow
        parent_depth = @workflow_run.metadata&.dig("sub_workflow_depth") ||
                       @workflow_run.runtime_context&.dig("sub_workflow_depth") ||
                       0
        parent_depth.to_i
      end
    end
  end
end
