# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Transform node executor - transforms data using configured rules
    class Transform < Base
      protected

      def perform_execution
        log_info "Transforming data"

        # Get transform configuration
        transform_type = configuration["transform_type"] || "map"
        input_variable = configuration["input_variable"]
        output_variable = configuration["output_variable"]

        # Get input data
        input = input_variable ? get_variable(input_variable) : input_data

        # Apply transformation
        transformed = case transform_type
        when "map"
                        apply_mapping(input)
        when "filter"
                        apply_filter(input)
        when "reduce"
                        apply_reduce(input)
        when "template"
                        apply_template(input)
        else
                        input
        end

        # Store transformed output
        if output_variable
          set_variable(output_variable, transformed)
        end

        log_debug "Transform complete: #{transform_type}"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: transformed,                   # Primary transformed result
          result: {                              # Computed transformation info
            transformation: transform_type,
            items_processed: transformed.is_a?(Array) ? transformed.count : 1
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "transform",
            executed_at: Time.current.iso8601,
            transform_type: transform_type
          }
        }
      end

      private

      def apply_mapping(input)
        mapping = configuration["mapping"] || {}

        if input.is_a?(Hash)
          result = {}
          mapping.each do |target_key, source_path|
            value = extract_value(input, source_path)
            result[target_key] = value if value.present?
          end
          result
        else
          input
        end
      end

      def apply_filter(input)
        filter_conditions = configuration["filter_conditions"] || {}

        if input.is_a?(Array)
          input.select do |item|
            matches_conditions?(item, filter_conditions)
          end
        else
          input
        end
      end

      def apply_reduce(input)
        reducer_function = configuration["reducer_function"] || "sum"

        if input.is_a?(Array)
          case reducer_function
          when "sum"
            input.sum
          when "count"
            input.count
          when "first"
            input.first
          when "last"
            input.last
          else
            input
          end
        else
          input
        end
      end

      def apply_template(input)
        template = configuration["template"] || ""

        # Simple variable substitution
        result = template.dup
        if input.is_a?(Hash)
          input.each do |key, value|
            result.gsub!("{{#{key}}}", value.to_s)
          end
        end
        result
      end

      def extract_value(data, path)
        return data if path.blank?

        path.to_s.split(".").reduce(data) do |current, key|
          break nil unless current.is_a?(Hash) || current.is_a?(Array)

          if current.is_a?(Array) && key =~ /\A\d+\z/
            current[key.to_i]
          else
            current[key.to_s] || current[key.to_sym]
          end
        end
      end

      def matches_conditions?(item, conditions)
        conditions.all? do |key, expected_value|
          item[key] == expected_value || item[key.to_sym] == expected_value
        end
      end
    end
  end
end
