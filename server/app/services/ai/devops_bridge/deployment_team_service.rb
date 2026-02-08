# frozen_string_literal: true

module Ai
  module DevopsBridge
    class DeploymentTeamService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Create a team from a DevOps template
      def create_deployment_team(template_id, params = {})
        template = Ai::DevopsTemplate.find_by!(account: account, id: template_id)

        team = Ai::AgentTeam.create!(
          account: account,
          name: params[:name] || "#{template.name} Deployment Team",
          description: params[:description] || "Auto-created from DevOps template: #{template.name}",
          team_type: "deployment",
          status: "active",
          metadata: {
            "devops_template_id" => template.id,
            "created_from" => "deployment_team_service",
            "infrastructure_bindings" => []
          }
        )

        # Provision agents from template configuration
        provision_agents_from_template(team, template)

        Rails.logger.info("Created deployment team #{team.name} from template #{template.name}")
        team
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error("DevOps template not found: #{template_id}")
        raise
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to create deployment team: #{e.message}")
        raise
      end

      # Associate team with infrastructure resources
      def bind_to_infrastructure(team, host_ids: [], cluster_ids: [])
        bindings = []

        host_ids.each do |host_id|
          host = Devops::DockerHost.find_by(account: account, id: host_id)
          next unless host

          bindings << { type: "docker_host", id: host.id, name: host.name }

          Ai::AgentConnection.find_or_create_by!(
            account: account,
            source_type: "Ai::AgentTeam",
            source_id: team.id,
            target_type: "Devops::DockerHost",
            target_id: host.id,
            connection_type: "infrastructure"
          ) do |conn|
            conn.status = "active"
            conn.strength = 1.0
            conn.discovered_by = "deployment_team_service"
          end
        end

        cluster_ids.each do |cluster_id|
          cluster = Devops::SwarmCluster.find_by(account: account, id: cluster_id)
          next unless cluster

          bindings << { type: "swarm_cluster", id: cluster.id, name: cluster.name }

          Ai::AgentConnection.find_or_create_by!(
            account: account,
            source_type: "Ai::AgentTeam",
            source_id: team.id,
            target_type: "Devops::SwarmCluster",
            target_id: cluster.id,
            connection_type: "infrastructure"
          ) do |conn|
            conn.status = "active"
            conn.strength = 1.0
            conn.discovered_by = "deployment_team_service"
          end
        end

        team.update!(
          metadata: team.metadata.merge(
            "infrastructure_bindings" => bindings
          )
        )

        Rails.logger.info("Bound team #{team.name} to #{bindings.size} infrastructure resources")
        bindings
      end

      # Queue a deployment execution for the team
      def execute_deployment(team, deployment_params)
        bindings = team.metadata&.dig("infrastructure_bindings") || []
        if bindings.empty?
          raise ArgumentError, "Team #{team.name} has no infrastructure bindings"
        end

        execution = Ai::TeamExecution.create!(
          account: account,
          agent_team: team,
          status: "pending",
          execution_type: "deployment",
          configuration: {
            "deployment_params" => deployment_params,
            "target_infrastructure" => bindings,
            "strategy" => deployment_params[:strategy] || "rolling"
          }
        )

        Rails.logger.info("Queued deployment execution #{execution.id} for team #{team.name}")
        execution
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to queue deployment: #{e.message}")
        raise
      end

      private

      def provision_agents_from_template(team, template)
        agent_configs = template.respond_to?(:agent_configurations) ? (template.agent_configurations || []) : []
        return if agent_configs.empty?

        autonomy_service = AgentAutonomyService.new(account: account)

        agent_configs.each do |config|
          autonomy_service.create_agent_for_team(
            team,
            {
              name: config["name"] || "#{template.name} Agent",
              description: config["description"] || "Provisioned from template",
              role: config["role"] || "worker"
            },
            nil
          )
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error("Failed to provision agent from template: #{e.message}")
        end
      end
    end
  end
end
