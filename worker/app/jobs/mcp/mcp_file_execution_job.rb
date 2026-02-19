# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Executes file operations dispatched from MCP workflow nodes
  # Queue: mcp
  # Retry: 2
  class McpFileExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 2, backtrace: true

    ALLOWED_OPERATIONS = %w[read write delete list copy move exists].freeze

    def execute(execution_id, payload = {})
      log_info("Starting file execution", execution_id: execution_id)

      started_at = Time.current
      operation = payload["operation"] || "read"
      storage_provider = payload["storage_provider"] || "local"
      object_key = payload["object_key"]

      unless ALLOWED_OPERATIONS.include?(operation)
        raise ArgumentError, "Invalid file operation: #{operation}"
      end

      log_info("File operation: #{operation} on #{storage_provider}://#{object_key}",
               execution_id: execution_id)

      # Perform the file operation
      result = perform_file_operation(operation, payload)

      report_execution_result(execution_id, {
        success: true,
        output: result.merge(
          operation: operation,
          storage_provider: storage_provider,
          object_key: object_key,
          executed_at: Time.current.iso8601
        ),
        duration_ms: ((Time.current - started_at) * 1000).to_i
      })

      log_info("File execution completed", execution_id: execution_id)
    rescue StandardError => e
      log_error("File execution failed", e, execution_id: execution_id)

      report_execution_result(execution_id, {
        success: false,
        error: e.message,
        duration_ms: ((Time.current - (started_at || Time.current)) * 1000).to_i
      })

      raise
    end

    private

    def perform_file_operation(operation, payload)
      case operation
      when "read"
        perform_read(payload)
      when "write"
        perform_write(payload)
      when "delete"
        perform_delete(payload)
      when "list"
        perform_list(payload)
      when "copy", "move"
        perform_transfer(operation, payload)
      when "exists"
        perform_exists(payload)
      else
        { message: "Operation #{operation} completed" }
      end
    end

    def perform_read(payload)
      path = safe_resolve_path(payload["object_key"])
      if path && ::File.exist?(path)
        { content: ::File.read(path), size: ::File.size(path) }
      else
        { content: nil, error: "File not found" }
      end
    end

    def perform_write(payload)
      path = safe_resolve_path(payload["object_key"])
      content = payload["content"]
      raise ArgumentError, "content is required for write operation" if content.blank?

      ::File.write(path, content) if path
      { written: true, size: content.to_s.bytesize }
    end

    def perform_delete(payload)
      path = safe_resolve_path(payload["object_key"])
      if path && ::File.exist?(path)
        ::File.delete(path)
        { deleted: true }
      else
        { deleted: false, error: "File not found" }
      end
    end

    def perform_list(payload)
      path = safe_resolve_path(payload["object_key"] || ".")
      if path && ::File.directory?(path)
        entries = Dir.entries(path).reject { |e| e.start_with?('.') }
        { objects: entries, count: entries.length }
      else
        { objects: [], count: 0 }
      end
    end

    def perform_transfer(operation, payload)
      source = safe_resolve_path(payload["source_key"])
      destination = safe_resolve_path(payload["destination_key"])
      raise ArgumentError, "source_key and destination_key are required" unless source && destination

      if operation == "copy"
        FileUtils.cp(source, destination)
      else
        FileUtils.mv(source, destination)
      end

      { "#{operation}d": true, source: source, destination: destination }
    end

    def perform_exists(payload)
      path = safe_resolve_path(payload["object_key"])
      { exists: path && ::File.exist?(path) }
    end

    def safe_resolve_path(path)
      return nil if path.blank?

      # Basic path traversal protection
      expanded = ::File.expand_path(path)
      if expanded.include?("..")
        raise ArgumentError, "Path traversal detected"
      end

      expanded
    end

    def report_execution_result(execution_id, result)
      api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
        status: result[:success] ? 'completed' : 'failed',
        result: result[:output],
        error_message: result[:error],
        execution_time_ms: result[:duration_ms]
      })
    rescue StandardError => e
      log_error("Failed to report execution result", e, execution_id: execution_id)
    end
  end
end
