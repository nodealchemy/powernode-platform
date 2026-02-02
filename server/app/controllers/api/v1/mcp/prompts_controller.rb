# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class PromptsController < ApplicationController
        before_action :set_mcp_server
        before_action :set_prompt, only: %i[show execute]

        # GET /api/v1/mcp/mcp_servers/:mcp_server_id/prompts
        def index
          prompts = discover_prompts

          render_success(
            prompts: prompts,
            mcp_server: {
              id: @mcp_server.id,
              name: @mcp_server.name,
              status: @mcp_server.status
            }
          )
        end

        # GET /api/v1/mcp/mcp_servers/:mcp_server_id/prompts/:id
        def show
          render_success(
            prompt: @prompt,
            mcp_server: {
              id: @mcp_server.id,
              name: @mcp_server.name
            }
          )
        end

        # POST /api/v1/mcp/mcp_servers/:mcp_server_id/prompts/:id/execute
        def execute
          result = execute_prompt(@prompt[:name], prompt_arguments)

          if result[:success]
            render_success(
              prompt_id: @prompt[:id],
              messages: result[:messages]
            )
          else
            render_error(result[:error], status: :unprocessable_entity)
          end
        end

        private

        def set_mcp_server
          @mcp_server = current_user.account.mcp_servers.find(params[:mcp_server_id])
        end

        def set_prompt
          prompts = discover_prompts
          @prompt = prompts.find { |p| p[:id] == params[:id] }

          unless @prompt
            render_error("Prompt not found", status: :not_found)
          end
        end

        def prompt_arguments
          params[:arguments]&.to_unsafe_h || {}
        end

        # Discover prompts from the MCP server
        # Prompts are discovered dynamically from the server's capabilities
        def discover_prompts
          return [] unless @mcp_server.connected?

          capabilities = @mcp_server.capabilities || {}
          return [] unless capabilities.dig("prompts")

          # Prompts are stored in the server's capabilities or fetched dynamically
          cached_prompts = capabilities.dig("discovered_prompts") || []

          cached_prompts.map.with_index do |prompt, index|
            {
              id: prompt["id"] || "prompt_#{index}",
              name: prompt["name"],
              description: prompt["description"],
              arguments: (prompt["arguments"] || []).map do |arg|
                {
                  name: arg["name"],
                  description: arg["description"],
                  required: arg["required"] || false
                }
              end
            }
          end
        end

        # Execute a prompt on the MCP server
        def execute_prompt(name, arguments)
          return { success: false, error: "Server not connected" } unless @mcp_server.connected?

          # Queue prompt execution via worker service
          begin
            result = WorkerJobService.execute_mcp_prompt(
              @mcp_server.id,
              prompt_name: name,
              arguments: arguments
            )

            {
              success: true,
              messages: result[:messages] || []
            }
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.error("Failed to execute MCP prompt: #{e.message}")
            { success: false, error: e.message }
          end
        end
      end
    end
  end
end
