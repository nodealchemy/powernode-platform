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
              # The executor destroys the cluster (Executors::Runtime::
              # DecommissionK3sCluster#perform). This closure used to call
              # `@cluster.destroy!` as well, which ran a second cascade over an
              # already-deleted row: `@cluster` is the instance loaded BEFORE
              # the gate, so its in-memory `persisted?` is still true and the
              # guard did not stop it. Logging and rendering stay here, because
              # those are exactly what must not happen on the parked or blocked
              # branches (IMP-4de09f201a0f).
              on_proceed: ->(_r) {
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
          #
          # AUDITED, FAIL-CLOSED, through the same writer as the MCP twin
          # (Ai::Tools::KubernetesProvisioningTool kubernetes_get_kubeconfig):
          # Ai::SensitiveAccessAudit. IMP-4ef95e825a7a audited that verb but
          # the guard sat on the VERB, not on the credential, and this endpoint
          # is the one the UI's kubeconfig button calls
          # (frontend/src/features/devops/kubernetes/services/kubernetesApi.ts)
          # — i.e. the path most retrievals actually take, reaching the same
          # material without entering the MCP layer at all.
          #
          # The row is written BEFORE the body is rendered. A post-hoc audit is
          # theatre: the credential would already be out. If the row cannot be
          # written the request is refused and nothing is disclosed.
          #
          # NEVER LOG THE MATERIAL. The row records that a retrieval happened,
          # by whom, for which cluster — never the kubeconfig itself.
          #
          # Returns 422 if the cluster is still bootstrapping (kubeconfig not
          # yet captured from the agent).
          def kubeconfig
            if @cluster.encrypted_kubeconfig.blank?
              return render_error(
                "kubeconfig not yet available — cluster is still bootstrapping (status=#{@cluster.status})",
                :unprocessable_content
              )
            end

            audit = ::Ai::SensitiveAccessAudit.record(
              account: current_user.account,
              user: current_user,
              resource_type: self.class.name,
              action_name: "devops.kubernetes.kubeconfig",
              context: { cluster_id: @cluster.id },
              principal: "user"
            )

            # nil is the writer's refusal signal. Fail closed: this action
            # releases credential material and is only permitted when the
            # access can be audited.
            unless audit
              return render_error(
                "kubeconfig refused: the access could not be audited. This endpoint releases " \
                "credential material and is only permitted when the access can be recorded.",
                :service_unavailable
              )
            end

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
