# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # File Download node executor
    # Downloads files from storage and makes them available to subsequent nodes
    class FileDownload < Base
      protected

      def perform_execution
        log_info "Executing File Download node"

        # Get file identifier
        file_id = configuration["file_id"] ||
                  get_variable(configuration["file_id_variable"]) ||
                  input_data&.dig("file_id")

        unless file_id
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "No file_id provided for download"
        end

        # Find file object
        file_object = ::FileObject.find_by(id: file_id, account: @orchestrator.account)
        unless file_object
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "File not found: #{file_id}"
        end

        log_debug "Downloading file: #{file_object.filename} (#{file_object.human_file_size})"

        # Create file storage service
        file_service = ::FileStorageService.new(
          @orchestrator.account,
          storage_config: file_object.file_storage
        )

        # Download file content
        file_content = file_service.download_file(file_object)

        # Store content in variable if configured
        if configuration["output_variable"]
          set_variable(configuration["output_variable"], file_content)
        end

        # Store as base64 if configured
        if configuration["base64_variable"]
          base64_content = Base64.strict_encode64(file_content)
          set_variable(configuration["base64_variable"], base64_content)
        end

        # Get file URL
        file_url = if configuration["signed_url"]
          file_service.file_url(
            file_object,
            signed: true,
            expires_in: configuration["url_expires_in"]&.to_i&.seconds || 1.hour
          )
        else
          file_service.file_url(file_object)
        end

        # Store URL in variable if configured
        if configuration["url_variable"]
          set_variable(configuration["url_variable"], file_url)
        end

        log_info "File downloaded successfully: #{file_object.filename}"

        # Prepare output format
        output_format = configuration["output_format"] || "metadata"

        output_data = case output_format
        when "content"
          # Return file content directly
          file_content
        when "base64"
          # Return base64 encoded content
          Base64.strict_encode64(file_content)
        when "url"
          # Return file URL
          file_url
        else
          # Default: return metadata with URL
          {
            file_id: file_object.id,
            filename: file_object.filename,
            file_size: file_object.file_size,
            content_type: file_object.content_type,
            url: file_url,
            checksum_md5: file_object.checksum_md5,
            checksum_sha256: file_object.checksum_sha256
          }
        end

        # Return standardized result
        {
          output: output_data,
          data: {
            file_object: file_object.file_summary,
            file_content_length: file_content.bytesize,
            storage_provider: file_object.file_storage.provider_type,
            category: file_object.category
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "file_download",
            executed_at: Time.current.iso8601,
            file_size_bytes: file_object.file_size,
            output_format: output_format
          }
        }
      rescue ::FileStorageService::FileNotFoundError => e
        log_error "File not found: #{e.message}"
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "File not found: #{e.message}"
      rescue StandardError => e
        log_error "File download failed: #{e.message}"
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "File download failed: #{e.message}"
      end
    end
  end
end
