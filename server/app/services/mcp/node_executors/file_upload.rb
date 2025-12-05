# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # File Upload node executor
    # Uploads files to configured storage provider from workflow context
    class FileUpload < Base
      protected

      def perform_execution
        log_info "Executing File Upload node"

        # Get file data from input or variables
        file_data = get_file_data
        unless file_data
          raise Mcp::WorkflowOrchestrator::NodeExecutionError, "No file data provided for upload"
        end

        # Get file metadata
        filename = configuration['filename'] || get_variable('filename') || 'uploaded_file'
        content_type = configuration['content_type'] || get_variable('content_type')
        category = configuration['category'] || 'workflow_output'

        # Get storage configuration
        storage_config = get_storage_config

        # Create file storage service
        file_service = ::FileStorageService.new(
          @orchestrator.account,
          storage_config: storage_config
        )

        log_debug "Uploading file: #{filename} (#{file_data.bytesize} bytes)"

        # Upload file
        file_object = file_service.upload_file(
          StringIO.new(file_data),
          filename: filename,
          content_type: content_type,
          category: category,
          description: configuration['description'],
          visibility: configuration['visibility'] || 'private',
          metadata: {
            'workflow_run_id' => @orchestrator.workflow_run.id,
            'node_id' => @node.node_id,
            'uploaded_by' => 'workflow'
          }.merge(configuration['metadata'] || {}),
          attachable: @orchestrator.workflow_run,
          uploaded_by_id: @orchestrator.user&.id,
          processing_tasks: configuration['processing_tasks'] || []
        )

        # Store file_id in variable if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], file_object.id)
        end

        # Store file_url in variable if configured
        if configuration['url_variable']
          file_url = file_service.file_url(file_object, signed: true, expires_in: 24.hours)
          set_variable(configuration['url_variable'], file_url)
        end

        log_info "File uploaded successfully: #{file_object.id}"

        # Return standardized result
        {
          output: {
            file_id: file_object.id,
            filename: file_object.filename,
            file_size: file_object.file_size,
            content_type: file_object.content_type,
            storage_key: file_object.storage_key,
            url: file_service.file_url(file_object)
          },
          data: {
            file_object: file_object.file_summary,
            storage_provider: storage_config.provider_type,
            category: category
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'file_upload',
            executed_at: Time.current.iso8601,
            file_size_bytes: file_object.file_size,
            storage_used_bytes: storage_config.total_size_bytes
          }
        }
      rescue ::FileStorageService::QuotaExceededError => e
        log_error "Storage quota exceeded: #{e.message}"
        raise Mcp::WorkflowOrchestrator::NodeExecutionError, "Storage quota exceeded: #{e.message}"
      rescue StandardError => e
        log_error "File upload failed: #{e.message}"
        raise Mcp::WorkflowOrchestrator::NodeExecutionError, "File upload failed: #{e.message}"
      end

      private

      def get_file_data
        # Check for file data in configuration
        if configuration['file_data'].present?
          return configuration['file_data']
        end

        # Check for file data from previous node
        if input_data.present? && input_data['file_data']
          return input_data['file_data']
        end

        # Check for file data in variable
        if configuration['file_data_variable']
          file_data = get_variable(configuration['file_data_variable'])
          return file_data if file_data.present?
        end

        # Check for URL to download from
        if configuration['source_url']
          return download_from_url(configuration['source_url'])
        end

        # Check for base64 encoded data
        if configuration['file_data_base64']
          return Base64.decode64(configuration['file_data_base64'])
        end

        nil
      end

      def get_storage_config
        # Use specified storage or account default
        if configuration['storage_id']
          storage = ::FileStorage.find_by(
            id: configuration['storage_id'],
            account: @orchestrator.account
          )
          unless storage
            raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                  "Storage configuration not found: #{configuration['storage_id']}"
          end
          storage
        else
          # Use default storage for account
          storage = @orchestrator.account.file_storages.default.first
          unless storage
            raise Mcp::WorkflowOrchestrator::NodeExecutionError,
                  "No default storage configuration found for account"
          end
          storage
        end
      end

      def download_from_url(url)
        require 'open-uri'

        log_debug "Downloading file from URL: #{url}"
        URI.open(url).read
      rescue StandardError => e
        log_error "Failed to download from URL: #{e.message}"
        raise Mcp::WorkflowOrchestrator::NodeExecutionError,
              "Failed to download file from URL: #{e.message}"
      end
    end
  end
end
