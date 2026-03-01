# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class ResourcesController < ApplicationController
        before_action :set_mcp_server
        before_action :set_resource, only: %i[show read]

        # GET /api/v1/mcp/mcp_servers/:mcp_server_id/resources
        def index
          resources = discover_resources

          render_success(
            resources: resources,
            mcp_server: {
              id: @mcp_server.id,
              name: @mcp_server.name,
              status: @mcp_server.status
            }
          )
        end

        # GET /api/v1/mcp/mcp_servers/:mcp_server_id/resources/:id
        def show
          render_success(
            resource: @resource,
            mcp_server: {
              id: @mcp_server.id,
              name: @mcp_server.name
            }
          )
        end

        # POST /api/v1/mcp/mcp_servers/:mcp_server_id/resources/:id/read
        def read
          content = read_resource_content(@resource[:uri])

          render_success(
            uri: @resource[:uri],
            content: content[:content],
            mime_type: content[:mime_type]
          )
        end

        private

        def set_mcp_server
          @mcp_server = current_user.account.mcp_servers.find(params[:mcp_server_id])
        end

        def set_resource
          resources = discover_resources
          @resource = resources.find { |r| r[:id] == params[:id] }

          unless @resource
            render_error("Resource not found", status: :not_found)
          end
        end

        # Discover resources from the MCP server
        # Resources are discovered dynamically from the server's capabilities
        def discover_resources
          return [] unless @mcp_server.connected?

          capabilities = @mcp_server.capabilities || {}
          return [] unless capabilities.dig("resources")

          # Resources are stored in the server's capabilities or fetched dynamically
          cached_resources = capabilities.dig("discovered_resources") || []

          cached_resources.map.with_index do |resource, index|
            {
              id: resource["id"] || "resource_#{index}",
              uri: resource["uri"],
              name: resource["name"],
              description: resource["description"],
              mime_type: resource["mimeType"] || resource["mime_type"]
            }
          end
        end

        # Read resource content from the MCP server
        def read_resource_content(uri)
          return { content: nil, mime_type: nil } unless @mcp_server.connected?

          # Queue resource read via worker service
          begin
            result = WorkerJobService.execute_mcp_resource_read(
              @mcp_server.id,
              uri: uri
            )

            {
              content: result[:content],
              mime_type: result[:mime_type]
            }
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.error("Failed to read MCP resource: #{e.message}")
            { content: nil, mime_type: nil, error: e.message }
          end
        end
      end
    end
  end
end
