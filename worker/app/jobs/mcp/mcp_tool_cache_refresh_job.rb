# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for refreshing the MCP tool cache across all connected servers
  # This is a periodic job that triggers tool discovery for all connected servers
  class McpToolCacheRefreshJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 2, backtrace: true

    def execute
      log_info("Starting MCP tool cache refresh")

      # Fetch all connected servers
      response = api_client.get("/api/v1/internal/mcp_servers?status=connected")

      unless response[:success]
        log_error("Failed to fetch connected servers")
        return
      end

      servers = response[:data][:mcp_servers] || []

      if servers.empty?
        log_info("No connected MCP servers for cache refresh")
        return
      end

      log_info("Refreshing tool cache for #{servers.count} MCP server(s)")

      # Queue tool discovery for each server
      servers.each do |server|
        McpToolDiscoveryJob.perform_async(server[:id])
      end

      log_info("Queued tool discovery for #{servers.count} MCP server(s)")
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP cache refresh", e)
      raise
    rescue StandardError => e
      log_error("Unexpected error during MCP cache refresh", e)
      raise
    end
  end
end
