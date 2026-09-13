# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # MANAGED DOCKER HOSTS (`Devops::DockerHost`) as components.
      #
      # ── SCOPE ───────────────────────────────────────────────────────────────
      # `Devops::DockerHost.where(account:)` — every row.
      #
      # This model has NO terminated, archived or soft-deleted state: the only
      # way a host leaves is `destroy`, and the reap arm then removes its status
      # row three sweeps later. `maintenance` is not an exclusion — it is
      # reversible operator intent, which the ladder spells `held`, and a host
      # under maintenance is precisely one the operator wants to keep seeing.
      #
      # ── WHY `error` IS `down` AND `disconnected` IS `degraded` ──────────────
      # `#record_failure!` only flips a host to `error` after
      # MAX_CONSECUTIVE_FAILURES consecutive failed syncs. `disconnected` is set
      # by an operator or a single failed connection and can clear on the next
      # sync; `error` means the platform has stopped being able to reach this
      # dockerd at all. `down` is reserved for total loss, and this is it.
      class DockerHost < Contributor
        include EnumConditions
        include SyncFreshness

        KIND = "docker_host"

        CONNECTED_TYPE = "Connected"

        # `Devops::DockerHost::STATUSES`, in full.
        STATUS_CONDITIONS = {
          "connected" => {
            type: CONNECTED_TYPE, status: true, reason: "Connected",
            message: "docker host is connected"
          },
          "pending" => {
            type: Condition::PROGRESSING_TYPE, status: true, reason: "AwaitingFirstConnection",
            message: "docker host has never completed a connection"
          },
          "maintenance" => {
            type: Condition::HELD_TYPE, status: true, reason: "Maintenance",
            message: "docker host was placed in maintenance by an operator"
          },
          "disconnected" => {
            type: CONNECTED_TYPE, status: false, severity: Condition::SEVERITY_DEGRADED,
            reason: "Disconnected",
            message: "docker host is not currently connected"
          },
          "error" => {
            type: CONNECTED_TYPE, status: false, severity: Condition::SEVERITY_DOWN,
            reason: "ConnectionError",
            message: "docker host has failed its connection checks repeatedly"
          }
        }.freeze

        def kind = KIND

        def each_component(account)
          return if account.blank?

          ::Devops::DockerHost.where(account_id: account.id)
                              .find_each { |host| yield host }
        end

        def ref_for(host) = host.id.to_s

        def display_name_for(host) = host.name.presence || host.slug

        def links_for(host)
          [ { "label" => "Docker host", "path" => "/app/devops/docker/#{host.id}" } ]
        end

        def presentation
          { "icon" => "Container", "label" => "Docker Host", "group_order" => 30 }
        end

        # Two claims: what the status column says, and whether we have heard
        # from the host recently enough to believe it. See SyncFreshness for
        # why an auto-sync-off host gets no freshness claim at all.
        def conditions_for(host)
          [
            enum_condition(
              host.status,
              table: STATUS_CONDITIONS,
              unknown_type: CONNECTED_TYPE,
              evidence: {
                "status" => host.status.to_s,
                "provisioning_state" => host.provisioning_state,
                "consecutive_failures" => host.consecutive_failures,
                "container_count" => host.container_count,
                "image_count" => host.image_count,
                "environment" => host.environment,
                "last_synced_at" => host.last_synced_at&.iso8601
              }.compact
            ),
            sync_freshness_condition(host)
          ].compact
        end

        # A `managed` host runs on exactly one NodeInstance (the 1:1 is enforced
        # by a unique index and a check constraint), and losing that instance
        # loses the dockerd — a real edge, so it is declared. An `external` host
        # is one an operator registered by endpoint; the platform models nothing
        # underneath it, so it gets no edge rather than a fabricated one.
        #
        # The FK column is read directly, never the association: in core mode
        # `System::NodeInstance` does not exist and the model falls back to a nil
        # reader, so loading the association would produce nothing while costing
        # a query per host.
        def dependencies_for(host)
          return [] if host.node_instance_id.blank?

          [ { "kind" => "node_instance", "ref" => host.node_instance_id.to_s, "relation" => "hosts" } ]
        end

        def actions_for(_host) = []

        # The docker daemon's own version is the closest thing this source has
        # to a generation.
        def observed_generation_for(host) = host.docker_version
      end
    end
  end
end
