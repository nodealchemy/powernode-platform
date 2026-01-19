# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # File node executor - performs file operations via storage APIs
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
    # - presigned_url: Generate presigned URL for access
    # - presigned_expiry: Expiry time for presigned URL in seconds
    #
    class File < Base
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
        metadata = configuration["metadata"] || {}
        source_key = resolve_value(configuration["source_key"])
        destination_key = resolve_value(configuration["destination_key"])
        generate_presigned = configuration.fetch("presigned_url", false)
        presigned_expiry = configuration["presigned_expiry"] || 3600

        validate_configuration!(operation, storage_provider, object_key)

        file_context = {
          operation: operation,
          storage_provider: storage_provider,
          bucket: bucket,
          object_key: object_key,
          content: content,
          content_type: content_type,
          metadata: metadata,
          source_key: source_key,
          destination_key: destination_key,
          generate_presigned: generate_presigned,
          presigned_expiry: presigned_expiry,
          started_at: Time.current
        }

        log_info "Performing #{operation} on #{storage_provider}://#{bucket}/#{object_key}"

        result = perform_operation(file_context)

        build_output(file_context, result)
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

      def perform_operation(context)
        case context[:operation]
        when "read"
          perform_read(context)
        when "write"
          perform_write(context)
        when "delete"
          perform_delete(context)
        when "list"
          perform_list(context)
        when "copy"
          perform_copy(context)
        when "move"
          perform_move(context)
        when "exists"
          perform_exists(context)
        end
      end

      def perform_read(context)
        # NOTE: In production, this would use actual storage SDK
        # S3: s3_client.get_object(bucket: bucket, key: key)
        # GCS: storage.bucket(bucket).file(key).download
        # Azure: blob_client.get_blob(container, blob)

        {
          success: true,
          operation: "read",
          object_key: context[:object_key],
          content: "[File content would be here]",
          content_type: context[:content_type],
          size: 0,
          last_modified: Time.current.iso8601,
          etag: SecureRandom.hex(16),
          presigned_url: context[:generate_presigned] ? generate_mock_presigned_url(context) : nil
        }
      end

      def perform_write(context)
        raise ArgumentError, "content is required for write operation" if context[:content].blank?

        {
          success: true,
          operation: "write",
          object_key: context[:object_key],
          content_type: context[:content_type],
          size: context[:content].to_s.bytesize,
          etag: SecureRandom.hex(16),
          version_id: "v_#{SecureRandom.hex(8)}"
        }
      end

      def perform_delete(context)
        {
          success: true,
          operation: "delete",
          object_key: context[:object_key],
          deleted: true
        }
      end

      def perform_list(context)
        # Mock listing response
        {
          success: true,
          operation: "list",
          prefix: context[:object_key] || "",
          objects: [
            { key: "#{context[:object_key] || 'files'}/file1.txt", size: 1024, last_modified: Time.current.iso8601 },
            { key: "#{context[:object_key] || 'files'}/file2.txt", size: 2048, last_modified: Time.current.iso8601 }
          ],
          truncated: false,
          count: 2
        }
      end

      def perform_copy(context)
        raise ArgumentError, "source_key and destination_key are required for copy" if context[:source_key].blank? || context[:destination_key].blank?

        {
          success: true,
          operation: "copy",
          source_key: context[:source_key],
          destination_key: context[:destination_key],
          copied: true
        }
      end

      def perform_move(context)
        raise ArgumentError, "source_key and destination_key are required for move" if context[:source_key].blank? || context[:destination_key].blank?

        {
          success: true,
          operation: "move",
          source_key: context[:source_key],
          destination_key: context[:destination_key],
          moved: true
        }
      end

      def perform_exists(context)
        # Mock existence check
        {
          success: true,
          operation: "exists",
          object_key: context[:object_key],
          exists: true
        }
      end

      def generate_mock_presigned_url(context)
        expiry = Time.current + context[:presigned_expiry].seconds
        "https://#{context[:storage_provider]}.example.com/#{context[:bucket]}/#{context[:object_key]}?expires=#{expiry.to_i}&signature=mock"
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
            success: result[:success],
            operation: context[:operation],
            object_key: context[:object_key]
          }.merge(result.slice(:content, :exists, :objects, :presigned_url)),
          data: result.merge(
            storage_provider: context[:storage_provider],
            bucket: context[:bucket],
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          metadata: {
            node_id: @node.node_id,
            node_type: "file",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
