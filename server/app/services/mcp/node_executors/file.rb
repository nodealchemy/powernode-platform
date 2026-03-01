# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # File node executor - dispatches file operations to worker
    #
    # Configuration:
    # - operation: read, write, delete, list, copy, move, exists
    # - storage_provider: s3, gcs, azure, local
    # - bucket: Storage bucket/container name
    # - object_key: Path to the object in storage
    # - content: Content to write (for write operation)
    # - content_type: MIME type for uploads
    # - metadata: Object metadata
    # - source_key: Source path for copy/move
    # - destination_key: Destination path for copy/move
    #
    class File < Base
      include Concerns::WorkerDispatch

      OPERATIONS = %w[read write delete list copy move exists].freeze
      STORAGE_PROVIDERS = %w[s3 gcs azure local].freeze

      protected

      def perform_execution
        log_info "Executing file operation"

        operation = configuration["operation"] || "read"
        storage_provider = configuration["storage_provider"] || "local"
        bucket = resolve_value(configuration["bucket"])
        object_key = resolve_value(configuration["object_key"])
        content = resolve_value(configuration["content"])
        content_type = configuration["content_type"] || "application/octet-stream"
        file_metadata = configuration["metadata"] || {}
        source_key = resolve_value(configuration["source_key"])
        destination_key = resolve_value(configuration["destination_key"])

        validate_configuration!(operation, storage_provider, object_key)

        payload = {
          operation: operation,
          storage_provider: storage_provider,
          bucket: bucket,
          object_key: object_key,
          content: content,
          content_type: content_type,
          file_metadata: file_metadata,
          source_key: source_key,
          destination_key: destination_key,
          node_id: @node.node_id
        }

        log_info "Dispatching #{operation} on #{storage_provider}://#{bucket}/#{object_key}"

        dispatch_to_worker("Mcp::McpFileExecutionJob", payload)
      end

      private

      def validate_configuration!(operation, storage_provider, object_key)
        unless OPERATIONS.include?(operation)
          raise ArgumentError, "Invalid operation: #{operation}. Allowed: #{OPERATIONS.join(', ')}"
        end

        unless STORAGE_PROVIDERS.include?(storage_provider)
          raise ArgumentError, "Invalid storage_provider: #{storage_provider}. Allowed: #{STORAGE_PROVIDERS.join(', ')}"
        end

        if %w[read write delete exists].include?(operation) && object_key.blank?
          raise ArgumentError, "object_key is required for #{operation} operation"
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
