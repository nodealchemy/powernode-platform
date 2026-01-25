# frozen_string_literal: true

module Api
  module V1
    module Mcp
      # Hosting Controller - Manage MCP hosted servers
      #
      # Handles server creation, deployment, lifecycle, and marketplace.
      #
      class HostingController < ApplicationController
        before_action :authenticate_request

        # GET /api/v1/mcp/hosting/servers
        def index
          result = hosting_service.list_servers(
            status: params[:status],
            visibility: params[:visibility],
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # GET /api/v1/mcp/hosting/servers/:id
        def show
          result = hosting_service.get_server(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :not_found)
          end
        end

        # POST /api/v1/mcp/hosting/servers
        def create
          result = hosting_service.create_server(server_params)

          if result
            render_success(result, status: :created)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH /api/v1/mcp/hosting/servers/:id
        def update
          result = hosting_service.update_server(params[:id], server_params)

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/mcp/hosting/servers/:id
        def destroy
          result = hosting_service.delete_server(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/deploy
        def deploy
          result = hosting_service.deploy_server(
            params[:id],
            version: params[:version],
            commit_sha: params[:commit_sha],
            user: current_user
          )

          if result
            render_success(result, status: :created)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/rollback
        def rollback
          result = hosting_service.rollback_deployment(
            params[:id],
            deployment_id: params[:deployment_id]
          )

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # GET /api/v1/mcp/hosting/servers/:id/deployments
        def deployments
          result = hosting_service.get_deployment_history(
            params[:id],
            limit: params[:limit]&.to_i || 20
          )

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :not_found)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/start
        def start
          result = hosting_service.start_server(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/stop
        def stop
          result = hosting_service.stop_server(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/restart
        def restart
          result = hosting_service.restart_server(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # GET /api/v1/mcp/hosting/servers/:id/metrics
        def metrics
          period = (params[:period_hours]&.to_i || 24).hours
          result = hosting_service.get_server_metrics(
            params[:id],
            period: period,
            granularity: params[:granularity] || "hourly"
          )

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :not_found)
          end
        end

        # GET /api/v1/mcp/hosting/servers/:id/health
        def health
          result = hosting_service.get_health_status(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :not_found)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/publish
        def publish
          result = hosting_service.publish_to_marketplace(
            params[:id],
            category: params[:category],
            price_usd: params[:price_usd],
            description: params[:description]
          )

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/mcp/hosting/servers/:id/unpublish
        def unpublish
          result = hosting_service.unpublish_from_marketplace(params[:id])

          if result
            render_success(result)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # GET /api/v1/mcp/hosting/marketplace
        def marketplace
          result = hosting_service.browse_marketplace(
            category: params[:category],
            search: params[:search],
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # POST /api/v1/mcp/hosting/marketplace/:server_id/subscribe
        def subscribe
          result = hosting_service.subscribe_to_server(
            params[:server_id],
            subscription_type: params[:subscription_type] || "free"
          )

          if result
            render_success(result, status: :created)
          else
            render_error(hosting_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # GET /api/v1/mcp/hosting/subscriptions
        def subscriptions
          result = hosting_service.get_subscriptions(
            status: params[:status],
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        private

        def hosting_service
          @hosting_service ||= ::Mcp::HostingService.new(current_account)
        end

        def server_params
          params.permit(
            :name, :description, :server_type, :source_type, :source_url,
            :source_branch, :source_path, :entry_point, :runtime, :visibility,
            environment_variables: {}, resource_limits: {}, capabilities: [],
            tool_manifest: {}
          )
        end
      end
    end
  end
end
