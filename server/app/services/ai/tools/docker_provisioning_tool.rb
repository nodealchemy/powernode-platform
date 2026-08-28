# frozen_string_literal: true

module Ai
  module Tools
    # Phase B — MCP-facing surface for the Docker daemon auto-provisioning
    # flow. Wraps `System::DockerDaemonProvisionerService` so operators
    # (and autonomy executors) can drive provision / decommission /
    # list-managed-hosts via the same `platform.*` action vocabulary
    # as the rest of the docker_* tools.
    #
    # Distinct from `DockerHostTool` (which manages *external*,
    # operator-registered hosts) because the lifecycle here is one-sided:
    # NodeInstance owns the host and the host is bound to the instance's
    # overlay /128. There's no "edit api_endpoint" semantic — the
    # endpoint is derived, not assigned.
    #
    # The two MUTATING actions route through `Ai::AutonomyGate` (see #gated):
    # provision under `system.runtime_docker_provision`, decommission under
    # `system.runtime_docker_decommission`. Those categories carry seeded
    # policy rows that RENDER in the Autonomy modal, and until IMP-9b9653e6514e
    # nothing read them — the operator's setting was a control wired to
    # nothing. `mark_ready` and the list action stay ungated deliberately: the
    # first is the agent's own heartbeat promotion (a heartbeat that parks for
    # approval is an outage), the second is a read.
    class DockerProvisioningTool < BaseTool
      # SECURITY (IMP-48abfa2f9e74): this floor used to be "docker.hosts.manage", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Docker::HostsController); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.docker.manage"

      def self.definition
        {
          name: "docker_provisioning",
          description: "Provision and decommission Docker daemons on managed Powernode NodeInstances",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            node_instance_id: { type: "string", required: false,
                                description: "System::NodeInstance ID — required for provision actions" },
            host_id: { type: "string", required: false,
                       description: "Devops::DockerHost ID, slug, or name — required for decommission/mark-ready" },
            docker_version: { type: "string", required: false,
                              description: "Daemon version reported by the agent (mark_ready)" }
          }
        }
      end

      def self.action_definitions
        {
          "system_provision_docker_runtime" => {
            description: "Auto-register a Docker daemon for a NodeInstance with the docker-engine module assigned. " \
                         "Returns the managed Devops::DockerHost row in 'pending' status; promote to 'connected' " \
                         "via system_mark_docker_ready once the agent confirms the daemon is listening.",
            parameters: {
              node_instance_id: { type: "string", required: true,
                                  description: "System::NodeInstance ID; must already have an Sdwan::Peer with an assigned overlay address" }
            }
          },
          "system_decommission_docker_runtime" => {
            description: "Tear down a managed Docker daemon: destroy the Devops::DockerHost row and purge its " \
                         "TLS material from Vault. The NodeInstance and its docker-engine module assignment " \
                         "are untouched — operator must unassign the module separately if they want the agent " \
                         "to stop dockerd.",
            parameters: {
              host_id: { type: "string", required: true, description: "Managed Docker host ID, slug, or name" }
            }
          },
          "system_mark_docker_ready" => {
            description: "Promote a pending managed Docker host to 'connected' status. Called by the heartbeat " \
                         "receiver once the agent reports the daemon is up and serving its CA-signed cert.",
            parameters: {
              host_id: { type: "string", required: true, description: "Managed Docker host ID, slug, or name" },
              docker_version: { type: "string", required: false,
                                description: "Daemon version string from the agent (e.g. '25.0.3')" }
            }
          },
          "system_list_managed_docker_hosts" => {
            description: "List Docker hosts auto-provisioned by NodeInstance (provisioning_state='managed'). " \
                         "Excludes operator-registered external hosts — use docker_list_hosts for those.",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "system_provision_docker_runtime"     then provision_runtime(params)
        when "system_decommission_docker_runtime"  then decommission_runtime(params)
        when "system_mark_docker_ready"            then mark_ready(params)
        when "system_list_managed_docker_hosts"    then list_managed_hosts(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      rescue ::System::DockerDaemonProvisionerService::ProvisionError => e
        # Covers the UNGATED actions only. Since IMP-9b9653e6514e the two
        # mutating actions reach the provisioner through Ai::AutonomyGate,
        # which rescues StandardError itself and answers :blocked — so a
        # provisioning failure there arrives as this method's `{ success:
        # false, error: }` via #gated's else branch, never here.
        { success: false, error: e.message }
      end

      private

      def provision_runtime(params)
        instance_id = params[:node_instance_id] or
          return { success: false, error: "node_instance_id is required" }

        # NodeInstance delegates account_id to its Node — no direct
        # column. Scoping through the join keeps account isolation, and it
        # runs BEFORE the gate so an id the caller may not see raises
        # RecordNotFound instead of parking an approval for someone else's
        # instance.
        instance = ::System::NodeInstance
                     .joins(:node)
                     .where(system_nodes: { account_id: account.id })
                     .find(instance_id)

        gated(
          action_category: "system.runtime_docker_provision",
          executor_class: "System::Executors::Runtime::ProvisionDockerHost",
          executor_params: { instance_id: instance.id },
          source_type: "System::NodeInstance",
          source_id: instance.id,
          description: "Provision Docker daemon on instance #{instance.name}"
        ) do |gate_result|
          host_id = gate_result.result&.dig(:data, :host_id)
          host = account.devops_docker_hosts.find_by(id: host_id)
          { success: true, host: host&.host_summary }
        end
      end

      def decommission_runtime(params)
        host = resolve_managed_host(params[:host_id]) or return managed_host_not_found_error(params[:host_id])

        gated(
          action_category: "system.runtime_docker_decommission",
          executor_class: "System::Executors::Runtime::DecommissionDockerHost",
          executor_params: { host_id: host.id },
          source_type: "Devops::DockerHost",
          source_id: host.id,
          description: "Decommission managed Docker host #{host.name}"
        ) do |_gate_result|
          { success: true, decommissioned: true, host_id: host.id }
        end
      end

      # Route a mutating action through Ai::AutonomyGate and translate the three
      # decisions into this tool's payload vocabulary. Mirrors the convention
      # SdwanTool#gated_result established for MCP callers; kept local because
      # the two tools answer in different shapes (this one returns bare
      # `{ success:, host: }` hashes, not BaseTool#success_result envelopes) and
      # a shared helper would have to own that difference.
      #
      # Agent AND user are both forwarded, which makes this tool the seam where
      # every audience is observable. The Runtime Manager's seeded rows are
      # agent-SCOPED, and Ai::InterventionPolicy#agent_matches? rejects a scoped
      # row against a nil agent — so only an agent-dispatched call resolves
      # against them. An operator MCP call arrives with @agent nil and matches
      # the scope-"action_type" rows seeded by
      # AgentSetupHelpers.upsert_operator_policies! instead.
      #
      # A scope-"global" row binds BOTH callers (IMP-cb36021d4094) — it is the
      # account-wide floor, so an operator's account-wide block refuses an agent
      # dispatch here rather than parking it for approval. With no row at all,
      # resolution falls to InterventionPolicyService#default_policy
      # (require_approval). @agent also buys attribution:
      # AutonomyGate#resolve_chain routes to "<agent name> Actions", and to
      # "Manual Operations" when nil.
      #
      # The block runs on the :proceed branch only, receiving the gate Result —
      # the executor has already run synchronously by then.
      def gated(action_category:, executor_class:, executor_params:, description:,
                source_type: nil, source_id: nil)
        result = ::Ai::AutonomyGate.evaluate(
          action_category: action_category,
          executor_class: executor_class,
          params: executor_params,
          account: account,
          agent: @agent,
          requested_by: @user,
          source_type: source_type,
          source_id: source_id,
          description: description
        )

        case result.decision
        when :proceed
          yield(result)
        when :pending
          {
            success: true,
            pending: true,
            action_category: action_category,
            deferred_operation_id: result.deferred_operation&.id,
            approval_request_id: result.approval_request&.id,
            message: "Approval required: #{action_category}"
          }
        else
          { success: false, error: result.error || "Action #{action_category} is blocked by policy" }
        end
      end

      def mark_ready(params)
        host = resolve_managed_host(params[:host_id]) or return managed_host_not_found_error(params[:host_id])
        ::System::DockerDaemonProvisionerService.new(docker_host: host).mark_daemon_ready!(
          host: host,
          docker_version: params[:docker_version]
        )
        { success: true, host: host.reload.host_summary }
      end

      def list_managed_hosts(_params)
        hosts = account.devops_docker_hosts.managed.order(:name)
        { success: true, hosts: hosts.map(&:host_summary), count: hosts.size }
      end

      def resolve_managed_host(identifier)
        return nil if identifier.blank?

        scope = account.devops_docker_hosts.managed
        scope.find_by(id: identifier) ||
          scope.find_by(slug: identifier) ||
          scope.find_by(name: identifier)
      end

      def managed_host_not_found_error(identifier)
        { success: false,
          error: "Managed Docker host not found: #{identifier} (only provisioning_state='managed' hosts are visible to this tool — use docker_list_hosts for external hosts)" }
      end
    end
  end
end
