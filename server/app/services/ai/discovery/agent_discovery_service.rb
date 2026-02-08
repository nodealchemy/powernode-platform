# frozen_string_literal: true

module Ai
  module Discovery
    class AgentDiscoveryService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Orchestrate a full discovery scan across all sources
      def run_full_scan
        result = create_discovery_result("full_scan")
        result.start!

        agents = []
        connections = []
        tools = []
        recommendations = []

        begin
          mcp_data = scan_mcp_servers
          agents.concat(mcp_data[:agents])
          tools.concat(mcp_data[:tools])
          connections.concat(mcp_data[:connections])

          infra_data = scan_docker_hosts
          agents.concat(infra_data[:agents])
          connections.concat(infra_data[:connections])

          swarm_data = scan_swarm_clusters
          agents.concat(swarm_data[:agents])
          connections.concat(swarm_data[:connections])

          task_data = scan_task_history
          recommendations.concat(task_data[:recommendations])

          result.complete!(
            agents: agents.uniq { |a| a[:id] },
            connections: connections,
            tools: tools,
            recommendations: recommendations
          )

          Rails.logger.info("Full scan completed: #{agents.size} agents, #{connections.size} connections, #{tools.size} tools")
        rescue StandardError => e
          result.fail!(e.message)
          Rails.logger.error("Full scan failed: #{e.message}")
          raise
        end

        result
      end

      # Scan MCP servers for agent-tool mappings
      def scan_mcp_servers
        result = create_discovery_result("mcp_scan")
        result.start!

        begin
          scanner = McpScannerService.new(account: account)
          data = scanner.scan

          result.complete!(
            agents: data[:agents],
            connections: data[:connections],
            tools: data[:tools]
          )
          data
        rescue StandardError => e
          result.fail!(e.message)
          { agents: [], connections: [], tools: [] }
        end
      end

      # Scan Docker hosts for agent containers
      def scan_docker_hosts
        result = create_discovery_result("docker_scan")
        result.start!

        begin
          scanner = InfrastructureScannerService.new(account: account)
          data = scanner.scan_docker_hosts

          result.complete!(
            agents: data[:agents],
            connections: data[:connections]
          )
          data
        rescue StandardError => e
          result.fail!(e.message)
          { agents: [], connections: [] }
        end
      end

      # Scan Swarm clusters for agent services
      def scan_swarm_clusters
        result = create_discovery_result("swarm_scan")
        result.start!

        begin
          scanner = InfrastructureScannerService.new(account: account)
          data = scanner.scan_swarm_clusters

          result.complete!(
            agents: data[:agents],
            connections: data[:connections]
          )
          data
        rescue StandardError => e
          result.fail!(e.message)
          { agents: [], connections: [] }
        end
      end

      # Analyze task history for recommendations
      def scan_task_history
        result = create_discovery_result("task_analysis")
        result.start!

        begin
          analyzer = TaskAnalyzerService.new(account: account)
          data = analyzer.analyze_history

          result.complete!(recommendations: data[:recommendations])
          data
        rescue StandardError => e
          result.fail!(e.message)
          { recommendations: [] }
        end
      end

      private

      def create_discovery_result(scan_type)
        Ai::DiscoveryResult.create!(
          account: account,
          scan_type: scan_type,
          status: "pending"
        )
      end
    end
  end
end
