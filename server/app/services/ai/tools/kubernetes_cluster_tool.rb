# frozen_string_literal: true

module Ai
  module Tools
    # Phase 2 — read-only inspection of Kubernetes clusters managed by
    # Powernode. Mirrors `DockerHostTool`'s shape: list, get, plus a
    # focused list_nodes for cluster membership inspection.
    #
    # Lifecycle operations (decommission, kubeconfig retrieval) live on
    # the sibling `KubernetesProvisioningTool` so the read/manage
    # permission split matches Docker's: docker.hosts.read for the
    # DockerHostTool surface, docker.hosts.manage for the provisioning
    # surface.
    class KubernetesClusterTool < BaseTool
      # SECURITY (IMP-48abfa2f9e74): this floor used to be "kubernetes.clusters.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Kubernetes::{Clusters,Nodes}Controller); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.kubernetes.read"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "kubernetes_get_cluster", mutating: false
      declare_action "kubernetes_list_clusters", mutating: false
      declare_action "kubernetes_list_nodes", mutating: false

      def self.definition
        {
          name: "kubernetes_cluster_management",
          description: "Read-only inspection of Kubernetes clusters managed by Powernode",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Cluster ID, slug, or name" }
          }
        }
      end

      def self.action_definitions
        {
          "kubernetes_list_clusters" => {
            description: "List all Kubernetes clusters in the account with status, flavor (k3s|kubeadm), node + pod counts",
            parameters: {}
          },
          "kubernetes_get_cluster" => {
            description: "Detailed info on a specific Kubernetes cluster including k8s_version, sync state, and metadata",
            parameters: {
              cluster_id: { type: "string", required: true, description: "Cluster ID, slug, or name" }
            }
          },
          "kubernetes_list_nodes" => {
            description: "List all member nodes of a Kubernetes cluster with their roles (server/agent/control_plane/worker) and status",
            parameters: {
              cluster_id: { type: "string", required: true, description: "Cluster ID, slug, or name" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "kubernetes_list_clusters" then list_clusters(params)
        when "kubernetes_get_cluster"   then get_cluster(params)
        when "kubernetes_list_nodes"    then list_nodes(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      def list_clusters(_params)
        clusters = account.devops_kubernetes_clusters.order(:name)
        {
          success: true,
          clusters: clusters.map(&:cluster_summary),
          count: clusters.size
        }
      end

      def get_cluster(params)
        cluster = resolve_cluster(params[:cluster_id]) or return cluster_not_found(params[:cluster_id])
        { success: true, cluster: cluster.cluster_details }
      end

      def list_nodes(params)
        cluster = resolve_cluster(params[:cluster_id]) or return cluster_not_found(params[:cluster_id])
        nodes = cluster.kubernetes_nodes.order(:role, :name)
        {
          success: true,
          cluster_id: cluster.id,
          nodes: nodes.map(&:node_summary),
          count: nodes.size
        }
      end

      def resolve_cluster(identifier)
        return nil if identifier.blank?

        scope = account.devops_kubernetes_clusters
        scope.find_by(id: identifier) ||
          scope.find_by(slug: identifier) ||
          scope.find_by(name: identifier)
      end

      def cluster_not_found(identifier)
        { success: false, error: "Kubernetes cluster not found: #{identifier}" }
      end
    end
  end
end
