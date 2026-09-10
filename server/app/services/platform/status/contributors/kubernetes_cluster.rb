# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # KUBERNETES CLUSTERS (`Devops::KubernetesCluster`) as components.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # `Devops::KubernetesCluster.where(account:)` — every row.
      #
      # Like `Devops::DockerHost`, this model has no terminated, archived or
      # soft-deleted state; a decommissioned cluster is destroyed (which also
      # releases its API VIP) and the reap arm removes the status row. There is
      # no maintenance/held state on this model at all — noted here so the
      # absence reads as a fact about the source rather than an oversight.
      #
      # ── `degraded` VS `error` ───────────────────────────────────────────────
      # `#record_failure!` flips a cluster to `degraded` after
      # MAX_CONSECUTIVE_FAILURES failed syncs; `error` is set by the
      # provisioning path when bootstrap itself failed. So `degraded` is a
      # cluster the platform is losing sight of and `error` is a cluster that
      # never came up — the second is total loss, the first is not.
      class KubernetesCluster < Contributor
        include EnumConditions

        KIND = "kubernetes_cluster"

        AVAILABLE_TYPE = "Available"

        # `Devops::KubernetesCluster::STATUSES`, in full.
        STATUS_CONDITIONS = {
          "active" => {
            type: AVAILABLE_TYPE, status: true, reason: "Active",
            message: "cluster API server is responding"
          },
          "pending" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "AwaitingBootstrap",
            message: "cluster has been created but not yet bootstrapped"
          },
          "bootstrapping" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "Bootstrapping",
            message: "cluster is bootstrapping"
          },
          "degraded" => {
            type: AVAILABLE_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "ClusterDegraded",
            message: "cluster has failed its sync checks repeatedly"
          },
          "disconnected" => {
            type: AVAILABLE_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "Disconnected",
            message: "cluster API server is not currently reachable"
          },
          "error" => {
            type: AVAILABLE_TYPE, status: false, severity: Condition::SEVERITY_DOWN,
            reason: "ClusterError",
            message: "cluster is in the error state"
          }
        }.freeze

        def kind = KIND

        def each_component(account)
          return if account.blank?

          ::Devops::KubernetesCluster.where(account_id: account.id)
                                     .includes(:kubernetes_nodes)
                                     .find_each { |cluster| yield cluster }
        end

        def ref_for(cluster) = cluster.id.to_s

        def display_name_for(cluster) = cluster.name.presence || cluster.slug

        def links_for(cluster)
          [ { "label" => "Cluster", "path" => "/app/devops/kubernetes/#{cluster.id}" } ]
        end

        def presentation
          { "icon" => "Boxes", "label" => "Kubernetes Cluster", "group_order" => 31 }
        end

        def conditions_for(cluster)
          [
            enum_condition(
              cluster.status,
              table: STATUS_CONDITIONS,
              unknown_type: AVAILABLE_TYPE,
              evidence: {
                "status" => cluster.status.to_s,
                "flavor" => cluster.flavor,
                "cni_plugin" => cluster.cni_plugin,
                "environment" => cluster.environment,
                "node_count" => cluster.node_count,
                "pod_count" => cluster.pod_count,
                "consecutive_failures" => cluster.consecutive_failures,
                "last_synced_at" => cluster.last_synced_at&.iso8601
              }.compact
            )
          ]
        end

        # Every member node is a NodeInstance the cluster runs on: lose them and
        # the cluster is gone, which is a real edge. The membership rows are
        # preloaded by `each_component`, so this reads them in memory rather
        # than issuing a query per cluster.
        def dependencies_for(cluster)
          cluster.kubernetes_nodes.filter_map do |node|
            next if node.node_instance_id.blank?

            { "kind" => "node_instance", "ref" => node.node_instance_id.to_s, "relation" => "hosts" }
          end
        end

        def actions_for(_cluster) = []

        def observed_generation_for(cluster) = cluster.k8s_version
      end
    end
  end
end
