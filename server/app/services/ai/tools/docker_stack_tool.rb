# frozen_string_literal: true

module Ai
  module Tools
    class DockerStackTool < BaseTool
      include Concerns::DockerContextResolvable

      # SECURITY (IMP-48abfa2f9e74): this floor used to be "swarm.stacks.read", a
      # name that appears ZERO times in config/permissions.rb. User#has_permission?
      # is an exact match on a role_permissions row plus a system.admin
      # short-circuit, so no row can ever exist for an undeclared name: every action
      # on this class was super-admin-only while tools/list advertised the whole
      # surface to everyone. b7598df74 created the devops.* family and moved the
      # REST twin onto it (Api::V1::Devops::Swarm::StacksController); this class was
      # missed by that sweep. Retargeted onto the same declared family, at the same
      # read/manage split the twin uses action for action.
      REQUIRED_PERMISSION = "devops.swarm.read"

      # The floor retarget ALONE would be an escalation: pointing it at a read
      # permission newly grants every read holder the write/exec actions sitting
      # behind it. ACTION_PERMISSIONS raises each of those to the manage tier,
      # enforced against the action that RUNS — never against the invoked name,
      # since a user principal is not pinned to it
      # (McpPlatformToolRegistrar#action_pinned_to_name?) and can supply a sibling
      # :action. Actions ABSENT from this map sit at the floor deliberately:
      #
      #   docker_list_stacks / docker_get_stack are DB reads (twin index/show).
      #   docker_adopt_stack is MANAGE despite reading like a discovery verb:
      #     SwarmManager#adopt_stack issues service_update against every
      #     matching LIVE Docker service to write the powernode.managed label,
      #     then creates or updates the SwarmStack row. It mutates the cluster.
      #   docker_deploy_stack / docker_delete_stack are the twin's deploy and
      #     remove_stack, both devops.swarm.manage.
      ACTION_PERMISSIONS = {
        "docker_deploy_stack" => "devops.swarm.manage",
        "docker_delete_stack" => "devops.swarm.manage",
        "docker_adopt_stack" => "devops.swarm.manage"
      }.freeze

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "docker_adopt_stack", mutating: true
      declare_action "docker_delete_stack", mutating: true
      declare_action "docker_deploy_stack", mutating: true
      declare_action "docker_get_stack", mutating: false
      declare_action "docker_list_stacks", mutating: false

      def self.definition
        {
          name: "docker_stack_management",
          description: "Manage Docker Swarm stacks: list, inspect, deploy, remove, adopt discovered stacks",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
            stack_id: { type: "string", required: false, description: "Stack UUID, slug, or name" },
            stack_name: { type: "string", required: false, description: "Stack name (for deploy/adopt)" },
            compose_file: { type: "string", required: false, description: "Docker Compose YAML content (for deploy)" },
            compose_variables: { type: "object", required: false, description: "Variable substitutions for compose file" }
          }
        }
      end

      def self.action_definitions
        {
          "docker_list_stacks" => {
            description: "List all Swarm stacks on a cluster with status, service count, and deployment history",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name (auto-selects if only one)" }
            }
          },
          "docker_get_stack" => {
            description: "Get detailed information about a stack including compose file and variables",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              stack_id: { type: "string", required: true, description: "Stack UUID, slug, or name" }
            }
          },
          "docker_deploy_stack" => {
            description: "Deploy or redeploy a stack from a Docker Compose YAML file. Provide compose_file for new stacks, or stack_id to redeploy an existing stack.",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              stack_id: { type: "string", required: false, description: "Existing stack to redeploy (UUID, slug, or name)" },
              stack_name: { type: "string", required: false, description: "Stack name (required for new stacks)" },
              compose_file: { type: "string", required: false, description: "Docker Compose YAML content" },
              compose_variables: { type: "object", required: false, description: "Variable substitutions (e.g. {\"IMAGE_TAG\": \"latest\"})" }
            }
          },
          "docker_delete_stack" => {
            description: "Remove a stack and all its services from the cluster",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              stack_id: { type: "string", required: true, description: "Stack UUID, slug, or name" }
            }
          },
          "docker_adopt_stack" => {
            description: "Adopt an existing Docker stack that was deployed outside Powernode. Tags its services as managed and creates a stack record.",
            parameters: {
              cluster_id: { type: "string", required: false, description: "Swarm cluster ID, slug, or name" },
              stack_name: { type: "string", required: true, description: "Name of the Docker stack to adopt (the com.docker.stack.namespace label)" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[DockerStackTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "docker_list_stacks" then list_stacks(params)
        when "docker_get_stack" then get_stack(params)
        when "docker_deploy_stack" then deploy_stack(params)
        when "docker_delete_stack" then remove_stack(params)
        when "docker_adopt_stack" then adopt_stack(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      rescue Devops::Docker::ApiClient::ApiError => e
        { success: false, error: "Docker API error: #{e.message}" }
      end

      private

      # Falls back to the class floor for the read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder (MemoryTool,
      # AgentAutonomyTool, SharedKnowledgeTool): in-process callers that opted in
      # with `internal: true`, and an mTLS node principal whose specific tool name
      # already cleared Mcp::Principal#may_invoke? and whose action the registrar
      # pinned to that same name. Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the MCP
        # path coerces a permission answer, and a truthy non-boolean must not read
        # as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

      def list_stacks(params)
        cluster = resolve_cluster(params[:cluster_id])
        stacks = cluster.swarm_stacks.order(:name)

        {
          success: true,
          cluster: { id: cluster.id, name: cluster.name },
          stacks: stacks.map { |s| s.stack_summary },
          count: stacks.size
        }
      end

      def get_stack(params)
        cluster = resolve_cluster(params[:cluster_id])
        stack = resolve_stack(cluster, params[:stack_id])
        services = cluster.swarm_services.where(stack: stack)

        {
          success: true,
          stack: stack.stack_details,
          services: services.map { |s| s.service_summary }
        }
      end

      def deploy_stack(params)
        cluster = resolve_cluster(params[:cluster_id])
        manager = Devops::Docker::StackManager.new(cluster: cluster, user: user)

        if params[:stack_id].present?
          # Redeploy existing stack
          stack = resolve_stack(cluster, params[:stack_id])

          if params[:compose_file].present?
            stack.update!(
              compose_file: params[:compose_file],
              compose_variables: params[:compose_variables] || stack.compose_variables
            )
          elsif params[:compose_variables].present?
            stack.update!(compose_variables: params[:compose_variables])
          end
        else
          # Create new stack
          name = params[:stack_name]
          return { success: false, error: "stack_name is required for new stack deployments" } if name.blank?
          return { success: false, error: "compose_file is required for new stack deployments" } if params[:compose_file].blank?

          stack = cluster.swarm_stacks.find_or_initialize_by(name: name)
          stack.assign_attributes(
            compose_file: params[:compose_file],
            compose_variables: params[:compose_variables] || {},
            source: "platform",
            status: "draft"
          )
          stack.save!
        end

        result = manager.deploy_stack(stack)
        result.merge(stack_id: stack.id, stack_name: stack.name)
      end

      def remove_stack(params)
        cluster = resolve_cluster(params[:cluster_id])
        stack = resolve_stack(cluster, params[:stack_id])
        manager = Devops::Docker::StackManager.new(cluster: cluster, user: user)

        result = manager.remove_stack(stack)
        result.merge(stack_name: stack.name)
      end

      def adopt_stack(params)
        cluster = resolve_cluster(params[:cluster_id])
        swarm_manager = Devops::Docker::SwarmManager.new(account: account)

        result = swarm_manager.adopt_stack(cluster, params[:stack_name])
        result
      end
    end
  end
end
