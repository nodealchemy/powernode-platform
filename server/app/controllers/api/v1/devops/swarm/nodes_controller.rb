# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Swarm
        class NodesController < ApplicationController
          include AuditLogging

          before_action :set_cluster
          before_action :set_node, only: %i[show promote demote drain activate remove]

          # GET /api/v1/devops/swarm/clusters/:cluster_id/nodes
          def index
            scope = @cluster.swarm_nodes

            scope = scope.where(role: params[:role]) if params[:role].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.order(role: :asc, hostname: :asc)

            render_success(items: scope.map(&:node_summary))
          end

          # GET /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id
          def show
            render_success(node: @node.node_details)
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id/promote
          def promote
            manager = ::Devops::Docker::NodeManager.new(cluster: @cluster)

            begin
              manager.promote(@node)
              render_success(node: @node.reload.node_details)
              log_audit_event("swarm.nodes.promote", @node)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Promote failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id/demote
          def demote
            manager = ::Devops::Docker::NodeManager.new(cluster: @cluster)

            begin
              manager.demote(@node)
              render_success(node: @node.reload.node_details)
              log_audit_event("swarm.nodes.demote", @node)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Demote failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id/drain
          def drain
            manager = ::Devops::Docker::NodeManager.new(cluster: @cluster)

            begin
              manager.drain(@node)
              render_success(node: @node.reload.node_details)
              log_audit_event("swarm.nodes.drain", @node)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Drain failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # POST /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id/activate
          def activate
            manager = ::Devops::Docker::NodeManager.new(cluster: @cluster)

            begin
              manager.activate(@node)
              render_success(node: @node.reload.node_details)
              log_audit_event("swarm.nodes.activate", @node)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Activate failed: #{e.message}", status: :unprocessable_content)
            end
          end

          # DELETE /api/v1/devops/swarm/clusters/:cluster_id/nodes/:id/remove
          def remove
            manager = ::Devops::Docker::NodeManager.new(cluster: @cluster)

            begin
              manager.remove(@node)
              render_success(message: "Node removed successfully")
              log_audit_event("swarm.nodes.remove", @node)
            rescue ::Devops::Docker::ApiClient::ApiError => e
              render_error("Remove failed: #{e.message}", status: :unprocessable_content)
            end
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_swarm_clusters.find(params[:cluster_id])
          end

          def set_node
            @node = @cluster.swarm_nodes.find(params[:id])
          end
        end
      end
    end
  end
end
