# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Database node executor - executes database operations
    #
    # Configuration:
    # - connection_id: Reference to stored database connection
    # - operation: query/insert/update/delete/transaction
    # - table: Target table name
    # - query: Raw SQL for query operation (with parameters)
    # - data: Key-value pairs for insert/update
    # - where: Conditions object
    # - limit: Result limit
    #
    class Database < Base
      ALLOWED_OPERATIONS = %w[query insert update delete count exists].freeze

      protected

      def perform_execution
        log_info "Executing database operation"

        operation = configuration["operation"] || "query"
        table = resolve_value(configuration["table"])
        query = resolve_value(configuration["query"])
        data = configuration["data"] || {}
        where_conditions = configuration["where"] || {}
        limit = configuration["limit"]

        validate_configuration!(operation, table, query)

        execution_context = {
          operation: operation,
          table: table,
          query: query,
          data: data,
          where: where_conditions,
          limit: limit,
          started_at: Time.current
        }

        log_info "Database operation: #{operation} on #{table || 'custom query'}"

        # Execute the operation
        result = execute_operation(execution_context)

        build_output(execution_context, result)
      end

      private

      def validate_configuration!(operation, table, query)
        unless ALLOWED_OPERATIONS.include?(operation)
          raise ArgumentError, "Invalid operation: #{operation}. Allowed: #{ALLOWED_OPERATIONS.join(', ')}"
        end

        if operation == "query" && query.blank?
          raise ArgumentError, "query is required for query operation"
        end

        if %w[insert update delete count exists].include?(operation) && table.blank?
          raise ArgumentError, "table is required for #{operation} operation"
        end

        # Security: Prevent SQL injection by checking for dangerous patterns
        validate_query_safety!(query) if query.present?
      end

      def validate_query_safety!(query)
        # Block dangerous statements in user queries
        dangerous_patterns = [
          /;\s*(DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)/i,
          /--.*$/,
          /\/\*.*\*\//,
          /UNION\s+ALL\s+SELECT/i
        ]

        dangerous_patterns.each do |pattern|
          if query.match?(pattern)
            raise ArgumentError, "Query contains potentially dangerous pattern"
          end
        end
      end

      def execute_operation(context)
        # NOTE: This is a simulation. In production, this would:
        # 1. Retrieve the database connection from connection_id
        # 2. Execute the actual database operation
        # 3. Return the results

        case context[:operation]
        when "query"
          simulate_query(context)
        when "insert"
          simulate_insert(context)
        when "update"
          simulate_update(context)
        when "delete"
          simulate_delete(context)
        when "count"
          simulate_count(context)
        when "exists"
          simulate_exists(context)
        end
      end

      def simulate_query(context)
        {
          rows: [],
          row_count: 0,
          columns: [],
          query_executed: context[:query]
        }
      end

      def simulate_insert(context)
        {
          inserted_id: SecureRandom.uuid,
          rows_affected: 1,
          table: context[:table],
          data_inserted: context[:data]
        }
      end

      def simulate_update(context)
        {
          rows_affected: 0,
          table: context[:table],
          data_updated: context[:data],
          conditions: context[:where]
        }
      end

      def simulate_delete(context)
        {
          rows_affected: 0,
          table: context[:table],
          conditions: context[:where]
        }
      end

      def simulate_count(context)
        {
          count: 0,
          table: context[:table],
          conditions: context[:where]
        }
      end

      def simulate_exists(context)
        {
          exists: false,
          table: context[:table],
          conditions: context[:where]
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
            operation_executed: true,
            operation: context[:operation],
            table: context[:table]
          },
          data: result.merge(
            operation: context[:operation],
            executed_at: Time.current.iso8601,
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          metadata: {
            node_id: @node.node_id,
            node_type: "database",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
