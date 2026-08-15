# frozen_string_literal: true

module Devops
  module Docker
    module Executors
      # Ai::AutonomyGate executor for tearing a Docker host down
      # (IMP-20fb59ec849d). Lives in CORE, and deliberately so.
      #
      # The gate needs an `executor_class` it can replay after an approver
      # decides, and the obvious candidate — the system extension's
      # Runtime::DecommissionDockerHost — cannot be named from a core
      # controller (core-purity gate #9). The operator ruling was to route
      # through a generic seam rather than baseline an exemption. Establishing
      # what the teardown actually NEEDS from the extension answered that
      # question differently from how it was posed: it needs nothing. The
      # credential store (Security::VaultCredentialProvider), the
      # `:docker_daemon_tls` credential type, the Devops::DockerHost model and
      # the managed/external distinction are all core. So there is no seam to
      # build — core simply owns a teardown that was already core-implementable,
      # and Devops::Docker::HostManager#remove_host stays the single place that
      # decides what a managed teardown involves.
      #
      # Contract (see the docstring on the system extension's executor base,
      # which this implements directly rather than inheriting — that base is
      # extension code):
      #
      #   .execute(params, deferred_operation:) → { success:, data: }
      #   .preview(params, deferred_operation:) → { summary:, impact: }
      #
      # Params: { host_id: <Devops::DockerHost id> }. They arrive through a
      # JSONB round-trip on the replay path, so keys are read indifferently.
      #
      # No replay-baseline stamping, deliberately. The extension base offers
      # `replay_baseline_attributes` for operations whose parked payload could
      # be applied over a row that moved underneath it; this operation carries
      # no payload to apply — the host either still exists at approval time
      # (and is destroyed) or does not (and resolve_host! raises, which
      # execute_now! declares as a failure). There is no state a stale premise
      # could silently overwrite.
      class DecommissionHost
        class << self
          def execute(params, deferred_operation:)
            host = resolve_host!(host_id(params), deferred_operation.account)
            ::Devops::Docker::HostManager
              .new(account: host.account)
              .remove_host(host)

            { success: true, data: { host_id: host.id, decommissioned: true } }
          end

          # Composes the approval card. `deferred_operation` here is an
          # Ai::DeferredOperation::PreviewContext (account and nothing else),
          # or nil when previewed before any operation exists.
          def preview(params, deferred_operation: nil)
            host = label_host(host_id(params), deferred_operation&.account)

            {
              summary: "Remove Docker host #{host&.name || host_id(params)}",
              impact: impact_for(host)
            }
          end

          private

          def host_id(params)
            p = params || {}
            p[:host_id] || p["host_id"]
          end

          # Always account-anchored, with no pass-through arm. The extension's
          # executor base keeps one because it has callers that reach it with a
          # literal nil; this has none — `execute` is only ever reached through
          # Ai::DeferredOperation#execute_now!, and that row `belongs_to
          # :account` (required), so `deferred_operation.account` cannot be
          # nil. An unreachable unscoped find would only be a cross-tenant read
          # waiting for a future caller; a nil account raises here instead, and
          # execute_now! fails the operation with it.
          #
          # This is the second of two anchors, not the only one: the gate
          # re-checks the source_type/source_id pair it recorded
          # (Ai::DeferredOperation#assert_source_within_account!) before the
          # replay. This one covers the id as the executor dereferences it.
          def resolve_host!(id, account)
            account.devops_docker_hosts.find(id)
          end

          # Three arms, not two. A nil host is NOT an external host: it also
          # covers "the row was deleted while this sat in approval", and
          # answering that case with the external wording would tell an
          # approver there is no TLS material at stake when there may be.
          def impact_for(host)
            return "Destroys the host record and everything attached to it" if host.nil?

            if host.managed?
              "Purges the daemon's TLS material from Vault and destroys the " \
                "host record, its containers, images, events and activities"
            else
              "Destroys the host record and its containers, images, events and activities"
            end
          end

          # Never raises: this names a row on a card shown to a human, and a
          # card that 500s is worse than one naming a bare id. Fails closed
          # with no anchor — an unanchored disclosure is exactly what
          # Ai::DeferredOperation::PreviewContext exists to prevent.
          def label_host(id, account)
            return nil if id.blank? || account.nil?

            account.devops_docker_hosts.find_by(id: id)
          end
        end
      end
    end
  end
end
