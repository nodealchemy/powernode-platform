# frozen_string_literal: true

# Phase 2 — Kubernetes via K3s (with Phase 3 kubeadm support pre-modeled
# via the `flavor` enum). Adds the cluster + node bookkeeping that the
# system extension's auto-provisioning flow will populate when operators
# assign `k3s-server` / `k3s-agent` modules to NodeInstances.
#
# Mirrors the shape of devops_docker_hosts where it makes sense — same
# environment + status enums, same TLS-credential storage pattern, same
# auto_sync + sync_interval pattern. Diverges on the relationship
# topology: a Devops::KubernetesCluster spans MULTIPLE NodeInstances via
# Devops::KubernetesNode (the join model carries role + per-node
# status), whereas a Devops::DockerHost is 1:1 with its NodeInstance.
#
# Pods + deployments table land in a follow-up migration. This slice is
# strictly the cluster + node identity layer — enough for the agent to
# auto-register a k3s-server NodeInstance and emit a kubeconfig, without
# yet syncing workload state.
class CreateKubernetesClusterManagementTables < ActiveRecord::Migration[8.1]
  def change
    # ================================================================
    # Kubernetes Clusters — account-scoped cluster identity
    # ================================================================
    create_table :devops_kubernetes_clusters, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      # API server endpoint — typically `https://[<sdwan-/128-of-first-server>]:6443`
      # for k3s clusters, or behind a VIP for kubeadm HA control planes.
      # Phase 3 kubeadm + 3-node etcd pattern uses an SDWAN VIP here.
      t.string :api_endpoint, null: false

      # Cluster flavor — set at create time, immutable. K3s ships first
      # (Phase 2). Kubeadm support lands in Phase 3 alongside HA control
      # plane + Cilium CNI.
      t.string :flavor, null: false, default: "k3s"

      t.string :environment, null: false, default: "development"
      t.string :status, null: false, default: "pending"

      # Reported version (e.g. "v1.30.4+k3s1"). Per-node versions live on
      # devops_kubernetes_nodes — they may differ during a rolling
      # upgrade.
      t.string :k8s_version

      # Encrypted credentials. Serialized as JSON of {value, key_id}
      # matching the existing Devops::DockerHost.encrypted_tls_credentials
      # pattern. Vault-first via Security::VaultCredentialProvider with
      # DB fallback.
      t.text :encrypted_kubeconfig
      t.text :encrypted_server_token  # k3s server-join token
      t.text :encrypted_agent_token   # k3s agent-join token (typically
                                      # same as server token in k3s; kept
                                      # separate so kubeadm can populate
                                      # both differently)
      t.string :encryption_key_id

      # Cached counts — sync job updates these. Avoids COUNT(*) on the
      # devops_kubernetes_nodes / pods tables for every UI render.
      t.integer :node_count, default: 0, null: false
      t.integer :pod_count, default: 0, null: false

      t.boolean :auto_sync, default: true, null: false
      t.integer :sync_interval_seconds, default: 60, null: false
      t.integer :consecutive_failures, default: 0, null: false
      t.datetime :last_synced_at
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :devops_kubernetes_clusters, :slug, unique: true
    add_index :devops_kubernetes_clusters, [ :account_id, :name ], unique: true
    add_index :devops_kubernetes_clusters, :status
    add_index :devops_kubernetes_clusters, :environment
    add_index :devops_kubernetes_clusters, :flavor

    add_check_constraint :devops_kubernetes_clusters,
      "flavor IN ('k3s', 'kubeadm')",
      name: "chk_kubernetes_clusters_flavor"
    add_check_constraint :devops_kubernetes_clusters,
      "environment IN ('staging', 'production', 'development', 'custom')",
      name: "chk_kubernetes_clusters_environment"
    add_check_constraint :devops_kubernetes_clusters,
      "status IN ('pending', 'bootstrapping', 'active', 'degraded', 'disconnected', 'error')",
      name: "chk_kubernetes_clusters_status"

    # ================================================================
    # Kubernetes Nodes — joins NodeInstance to a Cluster with role
    # ================================================================
    # A NodeInstance can only be a member of ONE cluster (unique FK).
    # The role field captures both K3s (server | agent) and kubeadm
    # (control_plane | worker) vocabularies — the model layer maps
    # them onto a flavor-aware predicate.
    create_table :devops_kubernetes_nodes, id: :uuid do |t|
      t.references :kubernetes_cluster, type: :uuid, null: false,
        foreign_key: { to_table: :devops_kubernetes_clusters, on_delete: :cascade },
        index: { name: "idx_k8s_nodes_cluster" }

      # FK to the system extension's NodeInstance. Deleting the
      # NodeInstance nullifies the link (the cluster row stays, but the
      # node entry is orphaned and the sync job marks it missing).
      t.references :node_instance, type: :uuid, null: false,
        foreign_key: { to_table: :system_node_instances, on_delete: :cascade },
        index: { unique: true, name: "idx_k8s_nodes_node_instance_unique" }

      # Kubernetes-side identity. The agent reports the kubelet's
      # registered name (e.g. `i-abc123-def`); we cache it here so
      # operators can correlate a NodeInstance row with kubectl output.
      t.string :name, null: false

      # k3s vocabulary (server | agent) — kubeadm vocabulary
      # (control_plane | worker) is also accepted via the check
      # constraint to keep Phase 3 a model-layer change rather than
      # a migration.
      t.string :role, null: false

      t.string :status, null: false, default: "pending"

      # Per-node kubelet version. May differ from the cluster's
      # reported k8s_version during a rolling upgrade.
      t.string :k8s_version

      t.datetime :last_heartbeat_at
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :devops_kubernetes_nodes, [ :kubernetes_cluster_id, :name ],
      unique: true, name: "idx_k8s_nodes_cluster_name"
    add_index :devops_kubernetes_nodes, :role
    add_index :devops_kubernetes_nodes, :status

    add_check_constraint :devops_kubernetes_nodes,
      "role IN ('server', 'agent', 'control_plane', 'worker')",
      name: "chk_kubernetes_nodes_role"
    add_check_constraint :devops_kubernetes_nodes,
      "status IN ('pending', 'joining', 'active', 'not_ready', 'disconnected', 'error')",
      name: "chk_kubernetes_nodes_status"
  end
end
