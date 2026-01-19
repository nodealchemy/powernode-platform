# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Loop node executor - iterates over collections and executes downstream nodes
    #
    # Configuration options:
    #   iteration_source: Path to collection (e.g., "data.items", "previous.results")
    #   item_variable: Variable name for current item (default: "item")
    #   index_variable: Variable name for current index (default: "index")
    #   max_iterations: Maximum allowed iterations (default: 1000)
    #   execution_mode: "serial" or "parallel" (default: "serial")
    #   break_on_error: Stop iteration on first error (default: true)
    #
    class Loop < Base
      DEFAULT_MAX_ITERATIONS = 1000
      DEFAULT_ITEM_VARIABLE = "item"
      DEFAULT_INDEX_VARIABLE = "index"

      protected

      def perform_execution
        log_info "Executing loop node"

        # Get configuration
        iteration_source = configuration["iteration_source"]
        item_variable = configuration["item_variable"] || DEFAULT_ITEM_VARIABLE
        index_variable = configuration["index_variable"] || DEFAULT_INDEX_VARIABLE
        max_iterations = (configuration["max_iterations"] || DEFAULT_MAX_ITERATIONS).to_i
        execution_mode = configuration["execution_mode"] || "serial"
        break_on_error = configuration.fetch("break_on_error", true)

        # Get collection to iterate over
        collection = resolve_iteration_source(iteration_source)

        # Validate collection
        unless collection.is_a?(Array) || collection.is_a?(Hash)
          log_error "Iteration source is not iterable: #{collection.class}"
          return error_result("Iteration source must be an array or hash")
        end

        # Convert hash to array of [key, value] pairs for iteration
        items = collection.is_a?(Hash) ? collection.to_a : collection

        # Validate against max iterations
        if items.length > max_iterations
          log_error "Collection exceeds max iterations: #{items.length} > #{max_iterations}"
          return error_result("Collection size (#{items.length}) exceeds maximum iterations (#{max_iterations})")
        end

        log_info "Iterating over #{items.length} items (mode: #{execution_mode})"

        # Execute iterations
        results = case execution_mode
        when "parallel"
                   execute_parallel(items, item_variable, index_variable, break_on_error)
        else
                   execute_serial(items, item_variable, index_variable, break_on_error)
        end

        # Build output
        successful_count = results.count { |r| r[:success] }
        failed_count = results.count { |r| !r[:success] }

        # Industry-standard output format (v1.0)
        {
          output: results.map { |r| r[:output] },
          result: {
            iterations_completed: results.length,
            iterations_successful: successful_count,
            iterations_failed: failed_count,
            loop_status: failed_count.zero? ? "completed" : "completed_with_errors"
          },
          data: {
            item_variable: item_variable,
            index_variable: index_variable,
            execution_mode: execution_mode,
            iteration_details: results.map { |r| { index: r[:index], success: r[:success] } }
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "loop",
            executed_at: Time.current.iso8601,
            total_items: items.length
          }
        }
      end

      private

      def resolve_iteration_source(source_path)
        return input_data if source_path.blank?

        # Handle special prefixes
        if source_path.start_with?("previous.")
          path = source_path.sub("previous.", "")
          resolve_path(previous_results, path)
        elsif source_path.start_with?("data.")
          path = source_path.sub("data.", "")
          resolve_path(input_data, path)
        elsif source_path.start_with?("$")
          # Variable reference
          variable_name = source_path[1..]
          get_variable(variable_name)
        else
          # Direct path on input data
          resolve_path(input_data, source_path)
        end
      end

      def resolve_path(data, path)
        return data if path.blank?
        return nil unless data.respond_to?(:[])

        parts = path.split(".")
        result = data

        parts.each do |part|
          if result.is_a?(Hash)
            result = result[part] || result[part.to_sym]
          elsif result.is_a?(Array) && part =~ /^\d+$/
            result = result[part.to_i]
          else
            return nil
          end
          return nil if result.nil?
        end

        result
      end

      def execute_serial(items, item_variable, index_variable, break_on_error)
        results = []

        items.each_with_index do |item, index|
          # Set iteration variables
          set_variable(item_variable, item)
          set_variable(index_variable, index)

          begin
            # Execute downstream nodes for this iteration
            iteration_result = execute_iteration_body(item, index)
            results << { index: index, success: true, output: iteration_result }
          rescue StandardError => e
            log_error "Iteration #{index} failed: #{e.message}"
            results << { index: index, success: false, output: nil, error: e.message }

            break if break_on_error
          end
        end

        results
      end

      def execute_parallel(items, item_variable, index_variable, break_on_error)
        # For parallel execution, we use threads with a mutex for safety
        results = Array.new(items.length)
        mutex = Mutex.new
        errors_occurred = false

        threads = items.each_with_index.map do |item, index|
          Thread.new do
            # Skip if error occurred and break_on_error is set
            next if break_on_error && errors_occurred

            begin
              # Note: Each thread gets its own variable scope conceptually
              # In practice, we execute the iteration body with the item directly
              iteration_result = execute_iteration_body(item, index)

              mutex.synchronize do
                results[index] = { index: index, success: true, output: iteration_result }
              end
            rescue StandardError => e
              mutex.synchronize do
                log_error "Parallel iteration #{index} failed: #{e.message}"
                results[index] = { index: index, success: false, output: nil, error: e.message }
                errors_occurred = true if break_on_error
              end
            end
          end
        end

        threads.each(&:join)

        # Filter out nil results (skipped due to break_on_error)
        results.compact
      end

      def execute_iteration_body(item, index)
        # The loop body is defined by downstream nodes connected to this loop node
        # For now, return the item as-is - the orchestrator handles downstream execution
        # based on the edge connections
        #
        # The item and index are available via get_variable for downstream nodes

        # If there's a transformation expression in configuration, apply it
        if configuration["transform_expression"].present?
          transform_item(item, configuration["transform_expression"])
        else
          item
        end
      end

      def transform_item(item, expression)
        # Simple transformation support
        # Example: "item.name" extracts the name from each item
        return item if expression.blank?

        if expression.start_with?("item.")
          path = expression.sub("item.", "")
          resolve_path(item.is_a?(Hash) ? item : { "value" => item }, path)
        else
          item
        end
      end

      def error_result(message)
        {
          output: [],
          result: {
            iterations_completed: 0,
            iterations_successful: 0,
            iterations_failed: 0,
            loop_status: "error",
            error_message: message
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "loop",
            executed_at: Time.current.iso8601,
            error: true
          }
        }
      end
    end
  end
end
