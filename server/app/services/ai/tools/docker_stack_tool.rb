# frozen_string_literal: true

module Ai
  module Tools
    class DockerStackTool < BaseTool
      include Concerns::DockerContextResolvable

      REQUIRED_PERMISSION = "swarm.stacks.read"

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
          "docker_remove_stack" => {
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
        case params[:action]
        when "docker_list_stacks" then list_stacks(params)
        when "docker_get_stack" then get_stack(params)
        when "docker_deploy_stack" then deploy_stack(params)
        when "docker_remove_stack" then remove_stack(params)
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
