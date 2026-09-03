# frozen_string_literal: true

module Ai
  module Tools
    # Phase 2 — Kubernetes cluster lifecycle operations + kubeconfig
    # retrieval. Manage-level permission required for everything here
    # because:
    #
    #   - decommission cascade-deletes the cluster + all member node
    #     rows (operators can't undo this without re-bootstrapping)
    #   - kubeconfig retrieval exposes the cluster's admin credentials
    #     in plaintext to the caller; equivalent to handing them root
    #     on every workload running in the cluster
    #
    # Cluster *creation* is intentionally NOT exposed here: the agent-
    # driven bootstrap flow handles cluster creation transparently.
    # Operators provision a k3s cluster by:
    #
    #   1. Assigning the `k3s-server` module to a NodeInstance via the
    #      standard module assignment API (System::NodeModuleAssignment
    #      CRUD).
    #   2. Waiting for the agent to install k3s + post phase=bootstrap
    #      to runtime/handshake. Cluster row appears in
    #      account.devops_kubernetes_clusters within ~60s.
    #
    # This surface is purely *operate on existing clusters*.
    class KubernetesProvisioningTool < BaseTool
      # SECURITY (IMP-48abfa2f9e74): this floor used to be "kubernetes.clusters.manage", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Kubernetes::ClustersController destroy + kubeconfig); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.kubernetes.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "kubernetes_decommission_cluster", mutating: true
      declare_action "kubernetes_get_kubeconfig", mutating: false

      def self.definition
        {
          name: "kubernetes_provisioning",
          description: "Manage Kubernetes cluster lifecycle and credentials",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Cluster ID, slug, or name" }
          }
        }
      end

      def self.action_definitions
        {
          "kubernetes_decommission_cluster" => {
            description: "Destroy a managed Kubernetes cluster: removes the cluster row and cascade-deletes all member " \
                         "Devops::KubernetesNode rows. The underlying NodeInstances are NOT terminated — they remain " \
                         "available for reuse. Operator must separately unassign the k3s-server / k3s-agent modules " \
                         "to fully clean up. Irreversible.",
            parameters: {
              cluster_id: { type: "string", required: true, description: "Cluster ID, slug, or name" }
            }
          },
          "kubernetes_get_kubeconfig" => {
            description: "Retrieve the kubeconfig YAML for a managed cluster. SENSITIVE: this is the cluster admin " \
                         "credential. Equivalent to root on every workload running in the cluster. Retrieval is " \
                         "recorded in the application log only — there is NO audit_logs entry for it.",
            parameters: {
              cluster_id: { type: "string", required: true, description: "Cluster ID, slug, or name" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "kubernetes_decommission_cluster" then decommission_cluster(params)
        when "kubernetes_get_kubeconfig"       then get_kubeconfig(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      def decommission_cluster(params)
        cluster = resolve_cluster(params[:cluster_id]) or return cluster_not_found(params[:cluster_id])

        cluster_id = cluster.id
        node_count = cluster.kubernetes_nodes.count
        cluster.destroy!

        Rails.logger.info(
          "[KubernetesProvisioningTool] decommissioned cluster cluster_id=#{cluster_id} " \
          "freed #{node_count} member node(s)"
        )

        {
          success: true,
          decommissioned: true,
          cluster_id: cluster_id,
          freed_node_count: node_count
        }
      end

      def get_kubeconfig(params)
        cluster = resolve_cluster(params[:cluster_id]) or return cluster_not_found(params[:cluster_id])

        if cluster.encrypted_kubeconfig.blank?
          return { success: false, error: "kubeconfig not yet available — cluster is still bootstrapping (status=#{cluster.status})" }
        end

        # NOTE: encrypted_kubeconfig is named for the storage column —
        # in v1 we store the raw YAML directly in the DB column.
        # Vault-backed storage rotates in via Security::VaultCredentialProvider
        # in a follow-up slice. The plaintext-under-an-encrypted-name shape is
        # why Devops::KubernetesCluster declares these columns on
        # `filter_attributes`: nothing keyed on `encrypts` can see them.
        #
        # The line below is the ONLY record of a retrieval. There is no audit
        # row: no MCP tool-call path writes one, and this tool writes none
        # itself. Do not describe this as forensic coverage.
        Rails.logger.info(
          "[KubernetesProvisioningTool] kubeconfig retrieved for cluster_id=#{cluster.id}"
        )

        {
          success: true,
          cluster_id: cluster.id,
          api_endpoint: cluster.api_endpoint,
          kubeconfig: cluster.encrypted_kubeconfig
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
