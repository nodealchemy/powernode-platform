# frozen_string_literal: true

module Devops
  # Core-side extension point for container lifecycle events (IMP-8880bc817ea3,
  # OVN container-fabric increment 2). Core owns the registry and the handler
  # contract and never names an extension; extensions register handlers in
  # their engine's boot initializers (the AttachableRegistry /
  # Ai::Land::SecurityScannerRegistry inversion-of-control pattern). With
  # nothing registered (core mode) every notify is a no-op, so core-only
  # assemblies are behaviorally unchanged.
  #
  # Events fire from Devops::DockerContainer commit callbacks — the single
  # funnel every container-record create/destroy path converges on:
  #
  #   CREATE  — Devops::Docker::ContainerManager#create_container (terminal
  #             actuator; reached from Api::V1::Devops::Docker::
  #             ContainersController#create and Ai::Tools::DockerContainerTool
  #             "docker_create_container"), Devops::Docker::HostManager
  #             #sync_containers / #import_containers (pull discovery), and
  #             Api::V1::Internal::Devops::DockerController#sync_containers
  #             (agent-push discovery).
  #   DESTROY — ContainerManager#remove_container (terminal actuator; same two
  #             callers), both discovery syncs' stale sweeps (`destroy_all`),
  #             and the Devops::DockerHost `dependent: :destroy` cascade.
  #
  # Devops::ContainerInstance / swarm workloads never call the Docker API from
  # Rails — any containers they cause materialize through the discovery syncs
  # above, so they still funnel through this seam.
  #
  # Handler contract: any callable responding to #call(event, container).
  # `event` is :created or :removed; `container` is the Devops::DockerContainer
  # record. Hooks run AFTER COMMIT — for :removed the record is destroyed, so
  # handlers must read its attributes and not traverse live associations
  # (a host-cascade destroy may have removed the parent row too). Handler
  # errors are logged and swallowed: a hook must never break container
  # lifecycle, since the container already exists (or is already gone) by the
  # time hooks run. Example (in an extension's boot initializer — core never
  # references the extension's class name):
  #
  #   Devops::ContainerLifecycleRegistry.register(:fabric) do |event, container|
  #     MyExt::FabricAllocator.call(event, container)
  #   end
  #
  # The register / unregister / registered? / names / handlers / reset! surface
  # is the shared ::Powernode::HandlerRegistry shape; @handlers memoizes on this
  # module, so this registry's state is its own. EVENTS and notify are this
  # registry's own.
  module ContainerLifecycleRegistry
    extend ::Powernode::HandlerRegistry

    EVENTS = %i[created removed].freeze

    class << self
      # Fan a lifecycle event out to every registered handler. Handler errors
      # are logged and swallowed (see contract above). Unknown events raise —
      # core call sites are fixed literals, so this only catches wiring typos.
      def notify(event, container)
        unless EVENTS.include?(event)
          raise ArgumentError, "unknown container lifecycle event #{event.inspect} (expected one of #{EVENTS.join(', ')})"
        end

        handlers.each do |name, handler|
          handler.call(event, container)
        rescue StandardError => e
          Rails.logger.error(
            "[ContainerLifecycleRegistry] #{name} hook failed for #{event} " \
            "on container #{container.try(:docker_container_id)}: #{e.message}"
          )
        end
        nil
      end

      private

      def handler_noun
        "lifecycle handler"
      end
    end
  end
end
