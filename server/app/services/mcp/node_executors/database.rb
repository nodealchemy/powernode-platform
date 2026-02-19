# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Database node executor - dispatches database operations to worker
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
      include Concerns::WorkerDispatch

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

        payload = {
          operation: operation,
          table: table,
          query: query,
          data: data,
          where: where_conditions,
          limit: limit,
          connection_id: configuration["connection_id"],
          node_id: @node.node_id
        }

        log_info "Database operation: #{operation} on #{table || 'custom query'}"

        dispatch_to_worker("Mcp::McpDatabaseExecutionJob", payload)
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

        validate_query_safety!(query) if query.present?
      end

      def validate_query_safety!(query)
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
