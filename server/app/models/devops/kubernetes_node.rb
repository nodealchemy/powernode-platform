# frozen_string_literal: true

module Devops
  # Phase 2 — joins a System::NodeInstance to a Devops::KubernetesCluster
  # with a role enum. One row per (cluster, instance) pair; a NodeInstance
  # can be a member of at most one cluster (DB-enforced via the unique
  # index on node_instance_id).
  #
  # Role vocabulary covers both K3s (server | agent) and Phase 3 kubeadm
  # (control_plane | worker). The model surfaces flavor-aware predicates
  # so callers don't have to know which vocabulary their cluster uses.
  class KubernetesNode < ApplicationRecord
    self.table_name = "devops_kubernetes_nodes"

    include Auditable

    # K3s vocabulary
    K3S_ROLES = %w[server agent].freeze
    # Kubeadm vocabulary
    KUBEADM_ROLES = %w[control_plane worker].freeze
    ROLES = (K3S_ROLES + KUBEADM_ROLES).freeze

    STATUSES = %w[pending joining active not_ready disconnected error].freeze

    belongs_to :kubernetes_cluster,
               class_name: "Devops::KubernetesCluster",
               foreign_key: :kubernetes_cluster_id
    belongs_to :node_instance,
               class_name: "System::NodeInstance",
               foreign_key: :node_instance_id

    validates :name, presence: true, length: { maximum: 255 }
    validates :role, presence: true, inclusion: { in: ROLES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :node_instance_id, uniqueness: true

    # name uniqueness scoped to the cluster (kubectl get nodes returns
    # unique names within a cluster; cross-cluster collisions are fine).
    validates :name, uniqueness: { scope: :kubernetes_cluster_id }

    scope :active, -> { where(status: "active") }
    scope :servers, -> { where(role: %w[server control_plane]) }
    scope :workers, -> { where(role: %w[agent worker]) }

    # ──────────────────────────────────────────────────────────────────
    # Flavor-aware role predicates — let callers ask "is this node
    # part of the control plane?" without knowing the cluster's flavor.
    # ──────────────────────────────────────────────────────────────────

    def server?
      role.in?(%w[server control_plane])
    end

    def worker?
      role.in?(%w[agent worker])
    end

    # ──────────────────────────────────────────────────────────────────
    # Status predicates
    # ──────────────────────────────────────────────────────────────────

    def active?       = status == "active"
    def pending?      = status == "pending"
    def joining?      = status == "joining"
    def not_ready?    = status == "not_ready"
    def disconnected? = status == "disconnected"

    # ──────────────────────────────────────────────────────────────────
    # Serialization helpers
    # ──────────────────────────────────────────────────────────────────

    def node_summary
      {
        id: id,
        kubernetes_cluster_id: kubernetes_cluster_id,
        node_instance_id: node_instance_id,
        name: name,
        role: role,
        status: status,
        k8s_version: k8s_version,
        last_heartbeat_at: last_heartbeat_at
      }
    end
  end
end
