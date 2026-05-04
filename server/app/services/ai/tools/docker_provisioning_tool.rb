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
    class DockerProvisioningTool < BaseTool
      REQUIRED_PERMISSION = "docker.hosts.manage"

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
        { success: false, error: e.message }
      end

      private

      def provision_runtime(params)
        instance_id = params[:node_instance_id] or
          return { success: false, error: "node_instance_id is required" }

        instance = ::System::NodeInstance.where(account_id: account.id).find(instance_id)
        host = ::System::DockerDaemonProvisionerService.provision!(
          node_instance: instance,
          account: account
        )
        { success: true, host: host.host_summary }
      end

      def decommission_runtime(params)
        host = resolve_managed_host(params[:host_id]) or return managed_host_not_found_error(params[:host_id])
        ::System::DockerDaemonProvisionerService.decommission!(docker_host: host)
        { success: true, decommissioned: true, host_id: host.id }
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
