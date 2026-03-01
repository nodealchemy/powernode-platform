# frozen_string_literal: true

module Ai
  module Discovery
    class InfrastructureScannerService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Scan Docker hosts for AI agent containers
      def scan_docker_hosts
        hosts = Devops::DockerHost.where(account: account)
        agents = Ai::Agent.where(account: account)

        discovered_agents = []
        discovered_connections = []

        hosts.find_each do |host|
          containers = host.docker_containers
          agent_containers = identify_agent_containers(containers, agents)

          agent_containers.each do |match|
            discovered_agents << {
              id: match[:agent_id],
              type: "agent",
              name: match[:agent_name],
              status: match[:container_status],
              metadata: {
                container_id: match[:container_id],
                host_id: host.id,
                host_name: host.name,
                infrastructure: "docker"
              }
            }

            discovered_connections << {
              source_type: "Ai::Agent",
              source_id: match[:agent_id],
              target_type: "Devops::DockerHost",
              target_id: host.id,
              connection_type: "infrastructure",
              strength: 1.0,
              metadata: {
                container_id: match[:container_id],
                container_name: match[:container_name]
              }
            }
          end
        end

        { agents: discovered_agents, connections: discovered_connections }
      end

      # Scan Swarm clusters for AI agent services
      def scan_swarm_clusters
        clusters = Devops::SwarmCluster.where(account: account)
        agents = Ai::Agent.where(account: account)

        discovered_agents = []
        discovered_connections = []

        clusters.find_each do |cluster|
          services = cluster.swarm_services
          agent_services = identify_agent_services(services, agents)

          agent_services.each do |match|
            discovered_agents << {
              id: match[:agent_id],
              type: "agent",
              name: match[:agent_name],
              status: match[:service_status],
              metadata: {
                service_id: match[:service_id],
                cluster_id: cluster.id,
                cluster_name: cluster.name,
                infrastructure: "swarm",
                replicas: match[:replicas]
              }
            }

            discovered_connections << {
              source_type: "Ai::Agent",
              source_id: match[:agent_id],
              target_type: "Devops::SwarmCluster",
              target_id: cluster.id,
              connection_type: "infrastructure",
              strength: 1.0,
              metadata: {
                service_id: match[:service_id],
                service_name: match[:service_name]
              }
            }
          end
        end

        { agents: discovered_agents, connections: discovered_connections }
      end

      # Build infrastructure connection records from scan results
      def build_infrastructure_connections(hosts, clusters, agents)
        connections = []

        hosts.each do |host|
          host.docker_containers.each do |container|
            matching_agent = find_matching_agent(container, agents)
            next unless matching_agent

            connections << build_connection(
              source: matching_agent,
              target_type: "Devops::DockerHost",
              target_id: host.id,
              metadata: { container_id: container.id }
            )
          end
        end

        clusters.each do |cluster|
          cluster.swarm_services.each do |service|
            matching_agent = find_matching_agent(service, agents)
            next unless matching_agent

            connections << build_connection(
              source: matching_agent,
              target_type: "Devops::SwarmCluster",
              target_id: cluster.id,
              metadata: { service_id: service.id }
            )
          end
        end

        connections
      end

      private

      def identify_agent_containers(containers, agents)
        matches = []
        agent_names = agents.pluck(:id, :name).to_h

        containers.each do |container|
          container_name = container.respond_to?(:name) ? container.name : ""
          container_labels = container.respond_to?(:labels) ? (container.labels || {}) : {}

          # Match by label
          agent_id = container_labels["ai.agent.id"] || container_labels["powernode.agent_id"]
          if agent_id && agent_names.key?(agent_id)
            matches << build_container_match(container, agent_id, agent_names[agent_id])
            next
          end

          # Match by name similarity
          agents.each do |agent|
            if container_name.downcase.include?(agent.name.downcase.gsub(/\s+/, "-"))
              matches << build_container_match(container, agent.id, agent.name)
              break
            end
          end
        end

        matches
      end

      def identify_agent_services(services, agents)
        matches = []

        services.each do |service|
          service_name = service.respond_to?(:name) ? service.name : ""
          service_labels = service.respond_to?(:labels) ? (service.labels || {}) : {}

          agent_id = service_labels["ai.agent.id"] || service_labels["powernode.agent_id"]
          if agent_id
            agent = agents.find_by(id: agent_id)
            if agent
              matches << build_service_match(service, agent)
              next
            end
          end

          agents.each do |agent|
            if service_name.downcase.include?(agent.name.downcase.gsub(/\s+/, "-"))
              matches << build_service_match(service, agent)
              break
            end
          end
        end

        matches
      end

      def build_container_match(container, agent_id, agent_name)
        {
          agent_id: agent_id,
          agent_name: agent_name,
          container_id: container.id,
          container_name: container.respond_to?(:name) ? container.name : nil,
          container_status: container.respond_to?(:status) ? container.status : "unknown"
        }
      end

      def build_service_match(service, agent)
        {
          agent_id: agent.id,
          agent_name: agent.name,
          service_id: service.id,
          service_name: service.respond_to?(:name) ? service.name : nil,
          service_status: service.respond_to?(:status) ? service.status : "unknown",
          replicas: service.respond_to?(:replicas) ? service.replicas : nil
        }
      end

      def find_matching_agent(resource, agents)
        name = resource.respond_to?(:name) ? resource.name.to_s.downcase : ""
        labels = resource.respond_to?(:labels) ? (resource.labels || {}) : {}

        agent_id = labels["ai.agent.id"] || labels["powernode.agent_id"]
        return agents.find_by(id: agent_id) if agent_id

        agents.detect { |a| name.include?(a.name.downcase.gsub(/\s+/, "-")) }
      end

      def build_connection(source:, target_type:, target_id:, metadata: {})
        {
          source_type: "Ai::Agent",
          source_id: source.id,
          target_type: target_type,
          target_id: target_id,
          connection_type: "infrastructure",
          strength: 1.0,
          metadata: metadata
        }
      end
    end
  end
end
