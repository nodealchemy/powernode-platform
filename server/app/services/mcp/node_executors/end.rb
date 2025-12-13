# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # End node executor - workflow exit point
    class End < Base
      protected

      def perform_execution
        log_info "Completing workflow execution"

        begin
          # Collect all previous node results with safety check
          all_results = previous_results || {}
          log_debug "Collected results from #{all_results.keys.size} previous nodes"

          # Determine the primary output from the workflow
          primary_output = extract_primary_output(all_results)

          # Apply output mapping if configured
          final_output = apply_output_mapping(all_results, primary_output)

          log_debug "Final output keys: #{final_output.keys.join(', ')}"
          log_info "Workflow completed with #{all_results.keys.size} node executions"

          # Safely access execution context
          execution_context = @orchestrator.respond_to?(:execution_context) ? @orchestrator.execution_context : {}
          execution_path = execution_context[:execution_path] || []
          input_variables = execution_context[:variables] || {}

          # Industry-standard output format (v1.0)
          # See: docs/platform/WORKFLOW_IO_STANDARD.md
          {
            output: "Workflow completed successfully",
            result: {
              status: "completed",
              final_output: final_output
            },
            data: {
              # CRITICAL FIX: Include all_node_outputs but exclude End node itself
              # This allows downstream nodes to access previous results while preventing
              # circular references when End node's result is stored back in @node_results
              # Filter out this End node's ID to prevent: @node_results['end_1'][:all_outputs]['end_1']
              all_node_outputs: all_results.reject { |node_id, _| node_id == @node.node_id },
              nodes_executed: all_results.keys,
              # Execution path taken through the workflow
              execution_path: execution_path,
              # Initial workflow variables
              input_variables: input_variables
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "end",
              executed_at: Time.current.iso8601,
              completed_at: Time.current.iso8601,
              total_duration_ms: calculate_total_duration(all_results),
              total_cost: calculate_total_cost(all_results),
              nodes_executed: all_results.keys.size,
              execution_mode: "collector"
            }
          }
        rescue StandardError => e
          # Log the actual error details before re-raising
          log_error "End node execution failed: #{e.message}"
          log_error "Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
          raise e
        end
      end

      private

      # Extract the primary output from the workflow execution
      # Typically this is the output from the last executed node
      def extract_primary_output(all_results)
        return {} if all_results.empty?

        # Get the last node's result
        last_node_id = all_results.keys.last
        last_result = all_results[last_node_id]

        return {} unless last_result.present?

        # CRITICAL FIX: Return the FULL last node output to preserve all detailed content
        # The previous implementation only extracted a single field (:output, :result, or :data)
        # which caused detailed markdown/content to be lost if it was nested in :data
        #
        # Now we return the complete structure so users get ALL the content:
        # - output: Status message
        # - result: Structured results
        # - data: Detailed content (markdown, etc.)
        # - metadata: Execution info
        #
        # This ensures preview and download get the full detailed output
        last_result
      end

      # Apply output mapping configuration if specified
      def apply_output_mapping(all_results, primary_output)
        output_mapping = configuration["output_mapping"] || {}

        if output_mapping.empty?
          # No explicit mapping - return FULL primary output (complete last node structure)
          # Safely access execution context
          execution_context = @orchestrator.respond_to?(:execution_context) ? @orchestrator.execution_context : {}
          input_variables = execution_context[:variables] || {}

          # CRITICAL FIX: Return the complete primary_output structure
          # primary_output now contains the FULL last node result (output, result, data, metadata)
          # We merge it with context info to provide complete workflow output
          final_output = primary_output.dup

          # Add context information
          final_output[:all_outputs] = all_results.reject { |node_id, _| node_id == @node.node_id }
          final_output[:variables] = input_variables

          final_output
        else
          # Apply explicit output mapping
          mapped_output = {}

          output_mapping.each do |output_key, source_path|
            value = resolve_output_path(source_path, all_results)
            mapped_output[output_key] = value if value.present?
          end

          mapped_output
        end
      end

      # Resolve output path from node results
      # Supports: {{node_id.output_key}}, {{input.variable}}, simple keys
      # Auto-parses JSON strings from node outputs
      def resolve_output_path(path, all_results)
        return path unless path.is_a?(String)

        # Match variable syntax: {{source.key}}
        if path =~ /^\{\{(.+?)\.(.+?)\}\}$/
          source = $1
          key = $2

          case source
          when "input"
            # Get from initial variables with safety check
            execution_context = @orchestrator.respond_to?(:execution_context) ? @orchestrator.execution_context : {}
            execution_context[:variables]&.dig(key)
          else
            # Get from node results
            node_result = all_results[source]
            if node_result.present?
              # STANDARD (v1.0): Check standard keys ONLY
              # See: docs/platform/WORKFLOW_IO_STANDARD.md
              # NO BACKWARD COMPATIBILITY

              if key == "output" && node_result[:output].present?
                return node_result[:output]
              elsif key == "result" && node_result[:result].present?
                return node_result[:result]
              elsif key == "data" && node_result[:data].present?
                return node_result[:data]
              end

              # Check data section for specific keys
              if node_result[:data].present?
                data_value = node_result[:data][key] || node_result[:data][key.to_sym]
                return data_value if data_value.present?
              end

              # ENHANCEMENT: Try to parse JSON from output field
              # If output is a JSON string and key doesn't match standard fields,
              # parse the JSON and extract the requested key
              if node_result[:output].present? && node_result[:output].is_a?(String)
                begin
                  parsed_output = JSON.parse(node_result[:output])
                  if parsed_output.is_a?(Hash)
                    # Try both string and symbol keys
                    value = parsed_output[key] || parsed_output[key.to_sym]
                    return value if value.present?
                  end
                rescue JSON::ParserError
                  # Not valid JSON, continue
                  log_debug "Could not parse output as JSON for #{source}.#{key}"
                end
              end

              # No match found
              nil
            end
          end
        else
          # Try to get as variable name
          get_variable(path)
        end
      end

      # Calculate total execution duration across all nodes
      def calculate_total_duration(all_results)
        return 0 if all_results.empty?

        total = 0
        all_results.each_value do |result|
          duration = result.dig(:metadata, :duration_ms)
          total += duration.to_i if duration.present?
        end
        total
      end

      # Calculate total cost across all nodes
      def calculate_total_cost(all_results)
        return 0.0 if all_results.empty?

        total = 0.0
        all_results.each_value do |result|
          cost = result.dig(:metadata, :cost)
          total += cost.to_f if cost.present?
        end
        total.round(6)
      end
    end
  end
end
