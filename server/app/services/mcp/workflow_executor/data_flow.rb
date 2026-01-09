# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module DataFlow
      # Build input data for node with edge data mapping support
      #
      # This method resolves input data for a node by:
      # 1. Reading edge data_mapping configuration from incoming edges
      # 2. Resolving variable paths like {{node_id.output_key}}
      # 3. Auto-passing previous results if no explicit mapping exists
      # 4. Including workflow variables as base context
      #
      # @param node [Ai::WorkflowNode] Node to build input for
      # @return [Hash] Input data with resolved mappings
      def build_node_input_data(node)
        input_data = {}

        # Get incoming edges to this node
        incoming_edges = @workflow.workflow_edges.where(target_node_id: node.node_id)

        # Track if any explicit mapping was found
        has_explicit_mapping = false

        # Process data mapping from each incoming edge
        incoming_edges.each do |edge|
          mapping_config = edge.configuration&.dig("data_mapping")

          if mapping_config.present?
            has_explicit_mapping = true
            log_debug "Applying data mapping for #{node.name}", {
              edge: "#{edge.source_node_id} → #{edge.target_node_id}",
              mappings: mapping_config.keys
            }

            # Apply each mapping rule
            mapping_config.each do |source_path, target_key|
              value = resolve_variable_path(source_path)

              if value.present?
                input_data[target_key] = value
                log_debug "Mapped #{source_path} → #{target_key}", {
                  value_type: value.class.name,
                  value_size: value.is_a?(String) ? value.length : nil
                }
              else
                log_warn "Could not resolve variable path", {
                  path: source_path,
                  target_key: target_key
                }
              end
            end
          end
        end

        # Auto-pass previous node outputs if no explicit mapping configured
        if !has_explicit_mapping && incoming_edges.any?
          log_debug "No explicit data mapping found, auto-passing previous results", {
            node: node.name,
            incoming_edges: incoming_edges.count
          }

          # Get the most recent previous node's output (for simple sequential flows)
          source_nodes = incoming_edges.map(&:source_node_id)

          source_nodes.each do |source_node_id|
            source_result = @node_results[source_node_id]

            if source_result.present? && source_result[:output_data].present?
              # Pass the output_data from previous node
              source_result[:output_data].each do |key, value|
                # Use namespaced keys to avoid conflicts
                namespaced_key = "#{source_node_id}_#{key}"
                input_data[namespaced_key] = value

                # Also pass without namespace if it's a standard key
                if key == "agent_output" || key == "output" || key == "result"
                  input_data[key] = value
                end
              end

              log_debug "Auto-passed data from #{source_node_id}", {
                keys: source_result[:output_data].keys
              }
            end
          end
        end

        # Always include workflow variables as base context
        @execution_context[:variables]&.each do |key, value|
          # Don't overwrite explicitly mapped or auto-passed data
          input_data[key] ||= value
        end

        log_info "Built input data for #{node.name}", {
          keys: input_data.keys,
          has_mapping: has_explicit_mapping,
          auto_passed: !has_explicit_mapping && incoming_edges.any?
        }

        input_data
      end

      # Resolve variable path expressions
      #
      # Supports formats:
      # - {{node_id.output_key}} -> Get output from specific node
      # - {{input.variable}} -> Get workflow input variable
      # - {{context.key}} -> Get from execution context
      # - Plain strings -> Return as-is
      #
      # @param path [String] Variable path to resolve
      # @return [Object, nil] Resolved value
      def resolve_variable_path(path)
        return path unless path.is_a?(String)

        # Match variable syntax: {{source.key}}
        if path =~ /^\{\{(.+?)\.(.+?)\}\}$/
          source = $1
          key = $2

          case source
          when "input"
            # Resolve from workflow input variables
            @execution_context[:variables]&.dig(key)

          when "context"
            # Resolve from execution context
            @execution_context&.dig(key.to_sym)

          else
            # Resolve from node results
            node_result = @node_results[source]

            if node_result.present?
              # Try to get from output_data first, then from top level
              node_result.dig(:output_data, key) || node_result.dig(key.to_sym)
            else
              log_warn "Could not find node result for #{source}"
              nil
            end
          end
        else
          # Return plain strings as-is
          path
        end
      end

      # Resolve nested path in hash
      #
      # @param data [Hash] Hash to traverse
      # @param path [String] Dot-separated path (e.g., "user.profile.name")
      # @return [Object, nil] Value at path
      def resolve_nested_path(data, path)
        return data if path.blank?

        keys = path.split(".")
        keys.reduce(data) do |current, key|
          break nil unless current.is_a?(Hash) || current.respond_to?(:[])

          # Try symbol and string keys
          current[key.to_sym] || current[key] || current[key.to_s]
        end
      end

      # Update execution context with node output
      #
      # @param node [Ai::WorkflowNode] Node that produced output
      # @param output_data [Hash] Output data from node
      def update_execution_context(node, output_data)
        @execution_context[:variables] ||= {}
        @execution_context[:execution_path] ||= []

        # Add to execution path
        @execution_context[:execution_path] << node.node_id

        # Store output under node ID namespace
        @execution_context[:node_outputs] ||= {}
        @execution_context[:node_outputs][node.node_id] = output_data
      end

      # Allow access to execution context (for node executors)
      def get_variable(name)
        @execution_context[:variables][name]
      end

      def set_variable(name, value)
        @execution_context[:variables][name] = value
        @workflow_run.update_column(:runtime_context, @execution_context)
      end
    end
  end
end
