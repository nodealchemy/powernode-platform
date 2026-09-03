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

    # The three encrypted_* columns are NOT `encrypts` attributes: v1 stores
    # the cluster-admin kubeconfig and both k3s node-join tokens as plaintext
    # under an encrypted_ name (see KubernetesProvisioningTool#get_kubeconfig).
    # Every mechanism that redacts by "is it encrypted?" therefore sees nothing
    # to redact here, so the columns are declared on Rails' own filtered-
    # attribute list instead — which masks them in #inspect and, because
    # Auditable honours the same list, in audit_logs old_values/new_values.
    # The delete snapshot is the copy that OUTLIVES the cluster row.
    # encryption_key_id is deliberately absent: it names a key, it is not one.
    self.filter_attributes += %i[encrypted_kubeconfig encrypted_server_token encrypted_agent_token]

    FLAVORS      = %w[k3s kubeadm].freeze
    ENVIRONMENTS = %w[staging production development custom].freeze
    STATUSES     = %w[pending bootstrapping active degraded disconnected error].freeze
    MAX_CONSECUTIVE_FAILURES = 5

    # Phase O4 — OVS+OVN dual-profile CNI selector. Picks which CNI the
    # K3s server boots with and (downstream in the integration step) the
    # `--flannel-backend=*` / `--disable-network-policy` flags the agent
    # passes to `k3s server`. Default is `flannel` because it ships in
    # K3s out of the box and works on every supported host. Promoting a
    # cluster to `ovn_kubernetes` is the deliberate heavyweight-profile
    # choice — see KubernetesClusterProvisionerService for the auto-
    # default selector that consults the bootstrap NodeInstance's
    # `network_profile`.
    CNI_PLUGINS = %w[flannel ovn_kubernetes].freeze

    # Lifecycle states past which `cni_plugin` is locked. Once K3s
    # has booted with a CNI choice, swapping it requires draining the
    # cluster and re-provisioning — the column is therefore immutable
    # once the cluster has left `pending`. Mirrors how `flavor` is set
    # at create time and never updated.
    CNI_LOCKED_STATUSES = (STATUSES - %w[pending]).freeze

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
    validates :cni_plugin, presence: true, inclusion: { in: CNI_PLUGINS }
    validates :sync_interval_seconds,
              numericality: { greater_than_or_equal_to: 30, less_than_or_equal_to: 3600 }

    # Phase O4 — `cni_plugin` is set at create time (or auto-defaulted by
    # the provisioner from the bootstrap NodeInstance's network_profile)
    # and locked once the cluster boots K3s. K3s only honours
    # `--flannel-backend=*` at server boot time; flipping CNI in place
    # would leave the running pods on the old plugin while new pods land
    # on the new one — so the model rejects updates past `pending`.
    validate :cni_plugin_immutable_after_bootstrap

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

    # Phase O4 — CNI partition. Used by the autonomy reconcile path
    # that surfaces "needs OVN install" pressure on heavyweight
    # clusters and the heavyweight-cluster operator dashboard.
    scope :cni_flannel, -> { where(cni_plugin: "flannel") }
    scope :cni_ovn_kubernetes, -> { where(cni_plugin: "ovn_kubernetes") }

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
    # CNI predicates + install-flag helper (Phase O4)
    # ──────────────────────────────────────────────────────────────────

    def cni_flannel?         = cni_plugin == "flannel"
    def cni_ovn_kubernetes?  = cni_plugin == "ovn_kubernetes"

    # Returns the K3s server install-flag list for this cluster's CNI
    # choice. The runtime config endpoint serves these to the on-node
    # agent, which appends them to the `k3s server` command line.
    #
    # Always returns an Array<String> so the wire payload is uniform —
    # callers can splat into `argv` directly without flattening / nil-
    # filtering. The wire shape stays the same when we add more
    # plugins (Cilium/Calico in a hypothetical Phase O5+).
    #
    #   flannel       → []  (K3s default; no extra args)
    #   ovn_kubernetes → ["--flannel-backend=none", "--disable-network-policy"]
    #
    # Class-level helper exists so callers that have the plugin string
    # but not a full cluster row (e.g. validation paths in the
    # provisioner) can still resolve flags without instantiating.
    def k3s_install_flags
      self.class.k3s_install_flags_for(cni_plugin)
    end

    def self.k3s_install_flags_for(plugin)
      case plugin.to_s
      when "flannel"
        # K3s ships Flannel with no extra args — explicit empty list keeps
        # the wire payload uniform for callers iterating across plugins.
        []
      when "ovn_kubernetes"
        # `--flannel-backend=none` tells K3s not to start its bundled
        # Flannel daemon; `--disable-network-policy` skips kube-proxy's
        # NetworkPolicy implementation because OVN-K8s ships its own.
        # Order matters for K3s argv determinism (the agent dedupes by
        # exact string match before merging with the operator-provided
        # extra_args list, so changing order would churn the diff).
        [ "--flannel-backend=none", "--disable-network-policy" ]
      else
        # Unknown plugin — return empty list rather than raising. The
        # validation layer is the source of truth for "is this plugin
        # known" and rejects unknown values at create/update time. If
        # an unknown value somehow lives on the row (DB hand-edit), the
        # safe behaviour is to fall back to no extra flags rather than
        # boot K3s with a poisoned argv.
        []
      end
    end

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
        cni_plugin: cni_plugin,
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

    # Phase O4 — CNI is set at K3s server bootstrap and immutable
    # thereafter. K3s only reads `--flannel-backend=*` /
    # `--disable-network-policy` at server boot time, so flipping the
    # column on a running cluster would silently leave the cluster on
    # the previously-installed CNI while platform metadata claims
    # otherwise. The model rejects updates past the `pending` state to
    # surface the contradiction loudly. Operators who genuinely need
    # to change CNI must drain + re-provision the cluster.
    def cni_plugin_immutable_after_bootstrap
      return unless persisted?
      return unless cni_plugin_changed?
      # The status column itself transitions through the lifecycle on
      # the same save (e.g. `pending` → `bootstrapping` when the agent
      # reports the K3s server is up). We need to read the *previously
      # persisted* status to decide whether the update is allowed —
      # not the in-memory value the caller is also trying to write.
      previous_status = status_in_database
      return if previous_status == "pending"

      errors.add(
        :cni_plugin,
        "is set at K3s server bootstrap and cannot change once the cluster " \
        "has left the 'pending' state (current status: #{previous_status}). " \
        "To change the CNI for this cluster, drain the workload, decommission " \
        "the cluster, and re-provision with the desired cni_plugin."
      )
    end

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
