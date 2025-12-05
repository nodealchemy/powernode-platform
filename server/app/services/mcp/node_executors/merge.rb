# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Merge node executor - combines outputs from multiple nodes
    class Merge < Base
      protected

      def perform_execution
        log_info "Merging node outputs"

        # Get merge strategy from configuration
        merge_strategy = configuration['merge_strategy'] || 'combine'

        # Get source node IDs from configuration or incoming edges
        source_node_ids = configuration['source_nodes'] || []

        # Collect outputs from source nodes
        # STANDARD (v1.0): Use standard keys ONLY - no backward compatibility
        merged_data = {}

        source_node_ids.each do |source_node_id|
          if previous_results[source_node_id].present?
            node_result = previous_results[source_node_id]

            # Standard format: Use output key only
            if node_result[:output].present?
              merged_data[source_node_id] = node_result[:output]
            end
          end
        end

        # Apply merge strategy
        final_output = case merge_strategy
                      when 'combine'
                        combine_outputs(merged_data)
                      when 'concatenate'
                        concatenate_outputs(merged_data)
                      when 'reduce'
                        reduce_outputs(merged_data)
                      else
                        merged_data
                      end

        # Store merged output in variable if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], final_output)
        end

        log_debug "Merged output: #{final_output.keys.join(', ')}"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: final_output,                  # Primary merged result
          result: {                              # Merge operation details
            strategy: merge_strategy,
            sources_merged: source_node_ids.count
          },
          data: {
            merged_from: source_node_ids
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'merge',
            executed_at: Time.current.iso8601,
            merge_strategy: merge_strategy,
            source_count: source_node_ids.count
          }
        }
      end

      private

      def combine_outputs(data)
        # Combine all outputs into a single hash
        combined = {}
        data.each do |node_id, output|
          if output.is_a?(Hash)
            combined.merge!(output)
          else
            combined[node_id] = output
          end
        end
        combined
      end

      def concatenate_outputs(data)
        # Concatenate all outputs into an array
        data.values.flatten
      end

      def reduce_outputs(data)
        # Reduce outputs based on configuration
        reducer_key = configuration['reducer_key'] || 'value'
        data.values.map { |output| output[reducer_key] }.compact
      end
    end
  end
end
