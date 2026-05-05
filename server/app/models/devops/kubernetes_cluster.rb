# frozen_string_literal: true

module Devops
  # Phase 2 — account-scoped Kubernetes cluster identity. Aggregates
  # devops_kubernetes_nodes (the per-NodeInstance memberships) and, in
  # a follow-up slice, devops_kubernetes_pods (workload state synced
  # from the cluster's API server).
  #
  # Lifecycle parallels Devops::DockerHost but with multiple
  # NodeInstance backers per cluster:
  #
  #   1. Operator creates the cluster (status: 'pending') with a
  #      designated bootstrap NodeInstance — typically the first
  #      `k3s-server` module assignee.
  #   2. Agent on bootstrap node provisions k3s, captures the kubeconfig
  #      + join tokens, posts them via the runtime/handshake endpoint.
  #      Cluster transitions to 'bootstrapping'.
  #   3. Once the API server responds + kubectl get nodes returns the
  #      bootstrap node as Ready, the cluster flips to 'active'.
  #   4. Subsequent `k3s-server` (HA control plane) or `k3s-agent`
  #      (worker) module assignments register as Devops::KubernetesNode
  #      rows attached to the cluster.
  class KubernetesCluster < ApplicationRecord
    self.table_name = "devops_kubernetes_clusters"

    include Auditable

    FLAVORS      = %w[k3s kubeadm].freeze
    ENVIRONMENTS = %w[staging production development custom].freeze
    STATUSES     = %w[pending bootstrapping active degraded disconnected error].freeze
    MAX_CONSECUTIVE_FAILURES = 5

    belongs_to :account
    has_many :kubernetes_nodes,
             class_name: "Devops::KubernetesNode",
             foreign_key: :kubernetes_cluster_id,
             dependent: :destroy
    # 1:N to NodeInstance via the join — convenience accessor for
    # ops UI + autonomy executors.
    has_many :node_instances,
             through: :kubernetes_nodes

    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9\-]+\z/ }
    validates :api_endpoint, presence: true, format: { with: /\Ahttps?:\/\// }
    validates :flavor, presence: true, inclusion: { in: FLAVORS }
    validates :environment, presence: true, inclusion: { in: ENVIRONMENTS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :sync_interval_seconds,
              numericality: { greater_than_or_equal_to: 30, less_than_or_equal_to: 3600 }

    # Phase 2.5 hardening (slice 3) — when the cluster goes away, its
    # api_endpoint VIP must go with it. Otherwise the VIP orphans on
    # the SDWAN network with no claimant. Best-effort cleanup —
    # rescued so VIP cleanup failures don't roll back cluster
    # decommission (operator can purge orphans via
    # `system_sdwan_delete_virtual_ip` if needed).
    before_destroy :destroy_api_vip!, prepend: true

    scope :active, -> { where(status: "active") }
    scope :auto_syncable, -> { where(auto_sync: true, status: "active") }
    scope :by_environment, ->(env) { where(environment: env) }
    scope :k3s,     -> { where(flavor: "k3s") }
    scope :kubeadm, -> { where(flavor: "kubeadm") }

    before_validation :generate_slug, on: :create

    # ──────────────────────────────────────────────────────────────────
    # Status predicates
    # ──────────────────────────────────────────────────────────────────

    def active?       = status == "active"
    def pending?      = status == "pending"
    def bootstrapping? = status == "bootstrapping"
    def degraded?     = status == "degraded"
    def disconnected? = status == "disconnected"

    # ──────────────────────────────────────────────────────────────────
    # Sync bookkeeping (mirrors DockerHost helpers)
    # ──────────────────────────────────────────────────────────────────

    def record_success!
      update!(
        status: "active",
        consecutive_failures: 0,
        last_synced_at: Time.current
      )
    end

    def record_failure!
      new_failures = consecutive_failures + 1
      new_status = new_failures >= MAX_CONSECUTIVE_FAILURES ? "degraded" : status
      update!(consecutive_failures: new_failures, status: new_status)
    end

    # ──────────────────────────────────────────────────────────────────
    # Serialization helpers
    # ──────────────────────────────────────────────────────────────────

    def cluster_summary
      {
        id: id,
        name: name,
        slug: slug,
        api_endpoint: api_endpoint,
        flavor: flavor,
        environment: environment,
        status: status,
        k8s_version: k8s_version,
        node_count: node_count,
        pod_count: pod_count,
        auto_sync: auto_sync,
        last_synced_at: last_synced_at,
        has_kubeconfig: encrypted_kubeconfig.present?
      }
    end

    def cluster_details
      cluster_summary.merge(
        description: description,
        sync_interval_seconds: sync_interval_seconds,
        consecutive_failures: consecutive_failures,
        metadata: metadata,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    private

    def destroy_api_vip!
      vip_id = (metadata || {})["api_vip_id"]
      return if vip_id.blank?
      return unless defined?(::Sdwan::VirtualIp) # system extension may be disabled
      ::Sdwan::VirtualIp.where(id: vip_id).destroy_all
    rescue StandardError => e
      Rails.logger.warn(
        "[Devops::KubernetesCluster] VIP cleanup failed for cluster_id=#{id} " \
        "vip_id=#{vip_id}: #{e.class}: #{e.message}. Operator can purge via " \
        "system_sdwan_delete_virtual_ip."
      )
    end

    def generate_slug
      return if slug.present?
      return if name.blank?

      base_slug = name.parameterize
      self.slug = base_slug

      counter = 1
      while Devops::KubernetesCluster.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end
  end
end
