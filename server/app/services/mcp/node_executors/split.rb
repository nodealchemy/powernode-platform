# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Split node executor - creates parallel execution branches from a single node
    #
    # Configuration options:
    #   strategy: "parallel" or "sequential" (default: "parallel")
    #   branches: Array of branch configurations (optional)
    #   merge_results: Whether to merge branch results (default: true)
    #   timeout_seconds: Timeout for parallel execution (default: 300)
    #
    class Split < Base
      DEFAULT_TIMEOUT_SECONDS = 300

      protected

      def perform_execution
        log_info "Executing split node"

        # Get configuration
        strategy = configuration["strategy"] || "parallel"
        timeout_seconds = (configuration["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
        merge_results = configuration.fetch("merge_results", true)

        # Identify branches from configuration or outgoing edges
        branches = identify_branches

        if branches.empty?
          log_info "No branches configured, passing through input data"
          return passthrough_result
        end

        log_info "Splitting into #{branches.length} branches (strategy: #{strategy})"

        # Execute branches based on strategy
        branch_results = case strategy
        when "sequential"
                          execute_sequential(branches)
        else
                          execute_parallel(branches, timeout_seconds)
        end

        # Build output
        successful_branches = branch_results.count { |_id, r| r[:success] }
        failed_branches = branch_results.count { |_id, r| !r[:success] }

        # Merge or collect results
        merged_output = if merge_results
                          merge_branch_results(branch_results)
        else
                          branch_results.transform_values { |r| r[:output] }
        end

        # Industry-standard output format (v1.0)
        {
          output: input_data, # Pass-through original input to branches
          result: {
            branches_created: branches.length,
            branches_successful: successful_branches,
            branches_failed: failed_branches,
            split_status: failed_branches.zero? ? "completed" : "completed_with_errors"
          },
          data: {
            strategy: strategy,
            branch_ids: branches.map { |b| b[:id] },
            branch_results: branch_results.transform_values do |r|
              { success: r[:success], has_output: r[:output].present? }
            end,
            merged_output: merged_output
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "split",
            executed_at: Time.current.iso8601,
            branch_count: branches.length
          }
        }
      end

      private

      def identify_branches
        # Priority 1: Explicit branch configuration
        if configuration["branches"].is_a?(Array)
          return configuration["branches"].map.with_index do |branch, idx|
            {
              id: branch["id"] || "branch_#{idx}",
              name: branch["name"] || "Branch #{idx + 1}",
              condition: branch["condition"],
              target_node: branch["target_node"]
            }
          end
        end

        # Priority 2: Get branches from outgoing edges
        outgoing_edges = @node.ai_workflow&.ai_workflow_edges
                              &.where(source_node_id: @node.node_id)&.to_a || []

        if outgoing_edges.any?
          return outgoing_edges.map do |edge|
            {
              id: edge.edge_id || edge.id,
              name: edge.label.presence || "Edge to #{edge.target_node_id}",
              condition: edge.condition,
              target_node: edge.target_node_id
            }
          end
        end

        # No branches found
        []
      end

      def execute_sequential(branches)
        results = {}

        branches.each do |branch|
          branch_id = branch[:id]

          begin
            # Check condition if present
            if branch[:condition].present? && !evaluate_condition(branch[:condition])
              log_debug "Branch #{branch_id} condition not met, skipping"
              results[branch_id] = { success: true, output: nil, skipped: true }
              next
            end

            # Execute branch
            output = execute_branch(branch)
            results[branch_id] = { success: true, output: output }
          rescue StandardError => e
            log_error "Branch #{branch_id} failed: #{e.message}"
            results[branch_id] = { success: false, output: nil, error: e.message }
          end
        end

        results
      end

      def execute_parallel(branches, timeout_seconds)
        results = {}
        mutex = Mutex.new
        deadline = Time.current + timeout_seconds

        threads = branches.map do |branch|
          Thread.new do
            branch_id = branch[:id]

            begin
              # Check timeout
              if Time.current > deadline
                mutex.synchronize do
                  results[branch_id] = { success: false, output: nil, error: "Timeout" }
                end
                next
              end

              # Check condition if present
              if branch[:condition].present? && !evaluate_condition(branch[:condition])
                log_debug "Branch #{branch_id} condition not met, skipping"
                mutex.synchronize do
                  results[branch_id] = { success: true, output: nil, skipped: true }
                end
                next
              end

              # Execute branch
              output = execute_branch(branch)

              mutex.synchronize do
                results[branch_id] = { success: true, output: output }
              end
            rescue StandardError => e
              mutex.synchronize do
                log_error "Branch #{branch_id} failed: #{e.message}"
                results[branch_id] = { success: false, output: nil, error: e.message }
              end
            end
          end
        end

        # Wait for all threads with timeout
        threads.each { |t| t.join(timeout_seconds) }

        # Mark timed-out branches
        branches.each do |branch|
          unless results.key?(branch[:id])
            results[branch[:id]] = { success: false, output: nil, error: "Execution timeout" }
          end
        end

        results
      end

      def execute_branch(branch)
        # The actual branch execution is handled by the orchestrator
        # This node prepares the context and routes to target nodes
        #
        # For branches with target_node, the orchestrator will handle
        # the actual execution of that node subtree
        #
        # Here we just pass the input data through

        if branch[:target_node].present?
          # Return reference to target node for orchestrator
          { target_node: branch[:target_node], input: input_data }
        else
          # No target, just pass through
          input_data
        end
      end

      def evaluate_condition(condition)
        return true if condition.blank?

        # Resolve variables in condition
        resolved = resolve_variables(condition)

        # Simple condition evaluation
        case resolved
        when /^true$/i
          true
        when /^false$/i
          false
        when /(.+)\s*(==|!=|>|<|>=|<=)\s*(.+)/
          left = $1.strip
          operator = $2
          right = $3.strip.gsub(/['"]/, "")
          evaluate_operator(left, operator, right)
        else
          resolved.present?
        end
      rescue StandardError => e
        log_error "Condition evaluation failed: #{e.message}"
        false
      end

      def evaluate_operator(left, operator, right)
        case operator
        when "==" then left.to_s == right.to_s
        when "!=" then left.to_s != right.to_s
        when ">"  then left.to_f > right.to_f
        when "<"  then left.to_f < right.to_f
        when ">=" then left.to_f >= right.to_f
        when "<=" then left.to_f <= right.to_f
        else false
        end
      end

      def resolve_variables(expression)
        return expression unless expression.is_a?(String)

        expression.gsub(/\{\{(\w+)\}\}/) do
          variable_name = $1
          value = get_variable(variable_name)
          value.present? ? value.to_s : "{{#{variable_name}}}"
        end
      end

      def merge_branch_results(results)
        merged = {}

        results.each do |branch_id, result|
          next unless result[:success] && result[:output].present?

          if result[:output].is_a?(Hash)
            merged.merge!(result[:output])
          else
            merged[branch_id] = result[:output]
          end
        end

        merged
      end

      def passthrough_result
        {
          output: input_data,
          result: {
            branches_created: 0,
            split_status: "passthrough"
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "split",
            executed_at: Time.current.iso8601,
            passthrough: true
          }
        }
      end
    end
  end
end
