# frozen_string_literal: true

module Api
  module V1
    module Devops
      module Kubernetes
        # Phase 2 — REST API for Devops::KubernetesCluster. Frontend
        # KubernetesHubPage hits these endpoints; the same URLs the
        # MCP layer already covers (kubernetes_list_clusters,
        # kubernetes_get_cluster, kubernetes_decommission_cluster).
        # Read endpoints map to the read MCP tool, destroy maps to the
        # provisioning MCP tool's decommission action.
        #
        # Cluster *creation* is intentionally not exposed here — it's
        # implicit via module assignment + agent bootstrap (same
        # rationale as the MCP layer; see KubernetesProvisioningTool).
        # Operators add clusters by assigning the k3s-server module to
        # a NodeInstance.
        class ClustersController < ApplicationController
          include ::Ai::GatedActions

          # Authorization on the dedicated devops.kubernetes.* family: reads
          # (index/show) -> devops.kubernetes.read. kubeconfig returns the cluster
          # *admin* credential and destroy decommissions the cluster, so both are
          # manage-tier -> devops.kubernetes.manage. destroy is ADDITIONALLY gated
          # through Ai::AutonomyGate (gate! below).
          before_action -> { require_permission("devops.kubernetes.read") }, only: %i[index show]
          before_action -> { require_permission("devops.kubernetes.manage") }, only: %i[destroy kubeconfig]
          before_action :set_cluster, only: %i[show destroy kubeconfig]

          # GET /api/v1/devops/kubernetes/clusters
          def index
            scope = current_user.account.devops_kubernetes_clusters
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(flavor: params[:flavor]) if params[:flavor].present?
            scope = scope.by_environment(params[:environment]) if params[:environment].present?
            scope = scope.order(created_at: :desc)

            render_success(items: scope.map(&:cluster_summary))
          end

          # GET /api/v1/devops/kubernetes/clusters/:id
          def show
            render_success(cluster: @cluster.cluster_details)
          end

          # DELETE /api/v1/devops/kubernetes/clusters/:id
          # Cascades to all member Devops::KubernetesNode rows. The
          # underlying NodeInstances are NOT terminated.
          #
          # Gated through Ai::AutonomyGate — cluster decommission is one of
          # the highest-blast operations in the platform (cascade-deletes
          # node rows, leaves workloads orphaned). Default policy is
          # require_approval per system_runtime_manager_agent.rb.
          def destroy
            cluster_id = @cluster.id
            cluster_name = @cluster.name
            node_count = @cluster.kubernetes_nodes.count

            gate!(
              action_category: "system.runtime_k8s_cluster_decommission",
              executor_class: "System::Executors::Runtime::DecommissionK3sCluster",
              params: { cluster_id: cluster_id },
              source_type: "Devops::KubernetesCluster",
              source_id: cluster_id,
              description: "Decommission K3s cluster '#{cluster_name}' (#{node_count} nodes)",
              on_proceed: ->(_r) {
                @cluster.destroy! if @cluster.persisted?
                Rails.logger.info(
                  "[Devops::Kubernetes::ClustersController] decommissioned " \
                  "cluster_id=#{cluster_id} freed #{node_count} member node(s)"
                )
                render_success(message: "Cluster decommissioned",
                               freed_node_count: node_count)
              }
            )
          end

          # GET /api/v1/devops/kubernetes/clusters/:id/kubeconfig
          # SENSITIVE: returns the cluster admin kubeconfig YAML.
          # Audit-logged. Returns 422 if the cluster is still
          # bootstrapping (kubeconfig not yet captured from the agent).
          def kubeconfig
            if @cluster.encrypted_kubeconfig.blank?
              return render_error(
                "kubeconfig not yet available — cluster is still bootstrapping (status=#{@cluster.status})",
                :unprocessable_content
              )
            end

            Rails.logger.info(
              "[Devops::Kubernetes::ClustersController] kubeconfig retrieved " \
              "for cluster_id=#{@cluster.id} by user_id=#{current_user.id}"
            )

            render_success(
              cluster_id: @cluster.id,
              api_endpoint: @cluster.api_endpoint,
              kubeconfig: @cluster.encrypted_kubeconfig
            )
          end

          private

          def set_cluster
            @cluster = current_user.account.devops_kubernetes_clusters.find_by(id: params[:id]) ||
                       current_user.account.devops_kubernetes_clusters.find_by(slug: params[:id]) ||
                       current_user.account.devops_kubernetes_clusters.find_by(name: params[:id])
            unless @cluster
              render_error("Cluster not found: #{params[:id]}", :not_found)
              return false
            end
            true
          end
        end
      end
    end
  end
end
