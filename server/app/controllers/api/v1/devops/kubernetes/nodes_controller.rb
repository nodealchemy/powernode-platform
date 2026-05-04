# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Kubernetes
        # Phase 2 — REST API for Devops::KubernetesNode. Read-only
        # from the operator UI's perspective: the agent reconciler
        # (slice 7) handles all node lifecycle through the
        # runtime/handshake endpoint.
        #
        # Routes are nested under cluster:
        #   GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes
        #   GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes/:id
        class NodesController < ApplicationController

          before_action :set_cluster
          before_action :set_node, only: %i[show]

          # GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes
          def index
            scope = @cluster.kubernetes_nodes
            scope = scope.where(role: params[:role]) if params[:role].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.order(:role, :name)

            render_success(
              cluster_id: @cluster.id,
              items: scope.map(&:node_summary)
            )
          end

          # GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes/:id
          def show
            render_success(node: @node.node_summary)
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_kubernetes_clusters.find_by(id: params[:cluster_id]) ||
                       current_user.account.devops_kubernetes_clusters.find_by(slug: params[:cluster_id])
            unless @cluster
              render_error("Cluster not found: #{params[:cluster_id]}", :not_found)
              return false
            end
            true
          end

          def set_node
            @node = @cluster.kubernetes_nodes.find_by(id: params[:id])
            unless @node
              render_error("Node not found: #{params[:id]}", :not_found)
              return false
            end
            true
          end
        end
      end
    end
  end
end
