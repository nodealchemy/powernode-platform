# frozen_string_literal: true

# Adds the `cni_plugin` column to `devops_kubernetes_clusters`. This is the
# cluster-level dial that picks which CNI the K3s server boots with (and,
# downstream in Phase O4+, which install-flags the agent passes to
# `k3s server`). CNI is uniform per cluster — every member node runs the
# same plugin — so the column lives on the cluster row, not the node row.
#
#   * `flannel` (default, safe everywhere) — K3s native CNI. No extra
#     install flags. Works on every supported host (lightweight + heavyweight
#     hardware floors). Pod-to-pod traffic uses VXLAN over the host's
#     primary NIC; pod traffic between nodes is therefore unencrypted on
#     the underlying network when SDWAN is not the primary path.
#   * `ovn_kubernetes` — OVN-Kubernetes CNI bolted onto a heavyweight K3s
#     cluster. K3s server runs with `--flannel-backend=none` +
#     `--disable-network-policy`; OVN-K8s is installed via Helm (or the
#     manifest path) at bootstrap. Pod-to-pod traffic rides OVN logical
#     switches over Geneve, with the Geneve endpoints pinned to SDWAN
#     overlay /128s — closing the pod encryption gap that motivates the
#     OVS+OVN heavyweight profile.
#
# Auto-default selection happens at cluster create time via the
# provisioner: it reads the bootstrap NodeInstance's `network_profile`
# (heavyweight → `ovn_kubernetes`, lightweight → `flannel`). Mixed-
# profile clusters are rejected at the application layer because CNI
# is uniform per cluster — operators must pick a profile for the whole
# cluster.
#
# Default is `flannel` because:
#   1. K3s ships it out of the box; zero extra install machinery.
#   2. It works on every supported host — no hardware floor risk.
#   3. Existing clusters that pre-date Phase O4 stay on Flannel via the
#      column default at backfill time, which mirrors their actual
#      runtime state.
#
# Immutability after bootstrap is enforced by the model. Once the
# cluster has progressed past the `pending` lifecycle state (i.e.
# `bootstrapping`, `active`, `degraded`, `disconnected`, `error`), the
# CNI choice is locked. Changing it requires a cluster drain + re-
# provision because K3s only honours `--flannel-backend` at server
# boot time.
#
# Phase O4 of the OVS+OVN dual-profile roadmap (heavyweight track —
# CNI selection foundation).
class AddCniPluginToDevopsKubernetesClusters < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME  = "chk_kubernetes_clusters_cni_plugin"
  ALLOWED_PLUGINS  = %w[flannel ovn_kubernetes].freeze
  COLUMN_DEFAULT   = "flannel"

  def up
    add_column :devops_kubernetes_clusters,
               :cni_plugin, :string,
               null: false, default: COLUMN_DEFAULT,
               comment: "OVS+OVN dual-profile CNI selector — see " \
                        "Devops::KubernetesCluster::CNI_PLUGINS"

    # Read-side filter for FleetAutonomyService / dashboards / heavyweight
    # cluster reports. Index is tiny (two distinct values across the
    # cluster fleet) but the equality scan is hot on the autonomy
    # reconcile path that surfaces "needs OVN install" pressure.
    add_index :devops_kubernetes_clusters, :cni_plugin,
              name: "index_devops_kubernetes_clusters_on_cni_plugin"

    add_check_constraint :devops_kubernetes_clusters,
      "cni_plugin IN (#{ALLOWED_PLUGINS.map { |p| "'#{p}'" }.join(', ')})",
      name: CONSTRAINT_NAME
  end

  def down
    remove_check_constraint :devops_kubernetes_clusters, name: CONSTRAINT_NAME
    remove_index :devops_kubernetes_clusters, name: "index_devops_kubernetes_clusters_on_cni_plugin"
    remove_column :devops_kubernetes_clusters, :cni_plugin
  end
end
