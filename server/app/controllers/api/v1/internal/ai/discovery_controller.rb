# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class DiscoveryController < InternalBaseController
          # GET /api/v1/internal/ai/discovery/mcp_servers
          def mcp_servers
            account = Account.find(params[:account_id])
            servers = account.mcp_servers.map do |s|
              { id: s.id, name: s.name, capabilities: s.capabilities, status: s.status }
            end
            render_success(servers)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # GET /api/v1/internal/ai/discovery/docker_hosts
          def docker_hosts
            account = Account.find(params[:account_id])
            hosts = account.devops_docker_hosts.includes(:docker_containers).map do |h|
              {
                id: h.id, name: h.name, status: h.status,
                containers: h.docker_containers.map { |c| { name: c.name, status: c.status } }
              }
            end
            render_success(hosts)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # GET /api/v1/internal/ai/discovery/swarm_clusters
          def swarm_clusters
            account = Account.find(params[:account_id])
            clusters = account.devops_swarm_clusters.includes(:swarm_services).map do |c|
              {
                id: c.id, name: c.name, status: c.status,
                services: c.swarm_services.map { |s| { name: s.name, status: s.status } }
              }
            end
            render_success(clusters)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # POST /api/v1/internal/ai/discovery/:scan_id/complete
          def complete
            result = ::Ai::DiscoveryResult.find_by!(scan_id: params[:scan_id])
            result.complete!(
              agents: params[:agents] || [],
              connections: params[:connections] || [],
              tools: params[:tools] || [],
              recommendations: params[:recommendations] || []
            )

            render_success(result.scan_summary)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Discovery Result")
          end

          # POST /api/v1/internal/ai/discovery/:scan_id/failed
          def failed
            result = ::Ai::DiscoveryResult.find_by!(scan_id: params[:scan_id])
            result.fail!(params[:error_message] || "Unknown error")

            render_success(result.scan_summary)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Discovery Result")
          end
        end
      end
    end
  end
end
