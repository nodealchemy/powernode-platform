# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Discovery::AgentDiscoveryService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  let(:mock_mcp_scanner) { instance_double(Ai::Discovery::McpScannerService) }
  let(:mock_infra_scanner) { instance_double(Ai::Discovery::InfrastructureScannerService) }
  let(:mock_task_analyzer) { instance_double(Ai::Discovery::TaskAnalyzerService) }

  let(:mcp_scan_data) do
    {
      agents: [{ id: "agent-1", name: "MCP Agent", type: "mcp" }],
      connections: [{ from: "agent-1", to: "tool-1" }],
      tools: [{ id: "tool-1", name: "Code Tool" }]
    }
  end

  let(:docker_scan_data) do
    {
      agents: [{ id: "agent-2", name: "Docker Agent", type: "container" }],
      connections: [{ from: "agent-2", to: "service-1" }]
    }
  end

  let(:swarm_scan_data) do
    {
      agents: [{ id: "agent-3", name: "Swarm Agent", type: "swarm" }],
      connections: [{ from: "agent-3", to: "cluster-1" }]
    }
  end

  let(:task_analysis_data) do
    {
      recommendations: [
        { type: "optimization", message: "Consider scaling agent-1" }
      ]
    }
  end

  before do
    allow(Ai::Discovery::McpScannerService).to receive(:new).and_return(mock_mcp_scanner)
    allow(Ai::Discovery::InfrastructureScannerService).to receive(:new).and_return(mock_infra_scanner)
    allow(Ai::Discovery::TaskAnalyzerService).to receive(:new).and_return(mock_task_analyzer)

    allow(mock_mcp_scanner).to receive(:scan).and_return(mcp_scan_data)
    allow(mock_infra_scanner).to receive(:scan_docker_hosts).and_return(docker_scan_data)
    allow(mock_infra_scanner).to receive(:scan_swarm_clusters).and_return(swarm_scan_data)
    allow(mock_task_analyzer).to receive(:analyze_history).and_return(task_analysis_data)
  end

  # ===========================================================================
  # #run_full_scan
  # ===========================================================================

  describe "#run_full_scan" do
    it "creates a discovery result and completes the scan" do
      result = service.run_full_scan

      expect(result).to be_a(Ai::DiscoveryResult)
      expect(result.status).to eq("completed")
      expect(result.scan_type).to eq("full_scan")
    end

    it "aggregates agents from all scanners" do
      result = service.run_full_scan

      expect(result.discovered_agents.length).to eq(3)
    end

    it "aggregates connections from all scanners" do
      result = service.run_full_scan

      expect(result.discovered_connections.length).to eq(3)
    end

    it "collects tools from MCP scan" do
      result = service.run_full_scan

      expect(result.discovered_tools.length).to eq(1)
      expect(result.tools_found).to eq(1)
    end

    it "collects recommendations from task analysis" do
      result = service.run_full_scan

      expect(result.recommendations.length).to eq(1)
    end

    it "deduplicates agents by id" do
      # Add a duplicate agent in swarm data
      allow(mock_infra_scanner).to receive(:scan_swarm_clusters).and_return(
        agents: [{ id: "agent-1", name: "MCP Agent Duplicate", type: "swarm" }],
        connections: []
      )

      result = service.run_full_scan

      # agent-1 appears twice but should be deduped
      expect(result.discovered_agents.length).to eq(2)
    end

    it "completes even when individual scanners fail (they rescue internally)" do
      allow(mock_mcp_scanner).to receive(:scan).and_raise(StandardError, "Scanner crashed")

      # Individual scan methods rescue errors and return empty data,
      # so run_full_scan still completes successfully with partial results
      result = service.run_full_scan

      expect(result.status).to eq("completed")
      # MCP agents missing, but docker + swarm agents still present
      expect(result.agents_found).to eq(2)
    end
  end

  # ===========================================================================
  # #scan_mcp_servers
  # ===========================================================================

  describe "#scan_mcp_servers" do
    it "delegates to McpScannerService and returns scan data" do
      data = service.scan_mcp_servers

      expect(data[:agents].length).to eq(1)
      expect(data[:tools].length).to eq(1)
      expect(data[:connections].length).to eq(1)
    end

    it "creates a completed discovery result" do
      service.scan_mcp_servers

      result = Ai::DiscoveryResult.where(account: account, scan_type: "mcp_scan").last
      expect(result.status).to eq("completed")
    end

    it "returns empty data on scanner failure" do
      allow(mock_mcp_scanner).to receive(:scan).and_raise(StandardError, "MCP error")

      data = service.scan_mcp_servers

      expect(data).to eq({ agents: [], connections: [], tools: [] })
    end

    it "records failure in discovery result when scanner errors" do
      allow(mock_mcp_scanner).to receive(:scan).and_raise(StandardError, "MCP error")

      service.scan_mcp_servers

      result = Ai::DiscoveryResult.where(account: account, scan_type: "mcp_scan").last
      expect(result.status).to eq("failed")
      expect(result.error_message).to eq("MCP error")
    end
  end

  # ===========================================================================
  # #scan_docker_hosts
  # ===========================================================================

  describe "#scan_docker_hosts" do
    it "delegates to InfrastructureScannerService for Docker hosts" do
      data = service.scan_docker_hosts

      expect(data[:agents].length).to eq(1)
      expect(data[:connections].length).to eq(1)
    end

    it "creates a completed discovery result" do
      service.scan_docker_hosts

      result = Ai::DiscoveryResult.where(account: account, scan_type: "docker_scan").last
      expect(result.status).to eq("completed")
    end

    it "returns empty data on failure" do
      allow(mock_infra_scanner).to receive(:scan_docker_hosts).and_raise(StandardError, "Docker error")

      data = service.scan_docker_hosts

      expect(data).to eq({ agents: [], connections: [] })
    end
  end

  # ===========================================================================
  # #scan_swarm_clusters
  # ===========================================================================

  describe "#scan_swarm_clusters" do
    it "delegates to InfrastructureScannerService for Swarm clusters" do
      data = service.scan_swarm_clusters

      expect(data[:agents].length).to eq(1)
      expect(data[:connections].length).to eq(1)
    end

    it "creates a completed discovery result" do
      service.scan_swarm_clusters

      result = Ai::DiscoveryResult.where(account: account, scan_type: "swarm_scan").last
      expect(result.status).to eq("completed")
    end

    it "returns empty data on failure" do
      allow(mock_infra_scanner).to receive(:scan_swarm_clusters).and_raise(StandardError, "Swarm error")

      data = service.scan_swarm_clusters

      expect(data).to eq({ agents: [], connections: [] })
    end
  end

  # ===========================================================================
  # #scan_task_history
  # ===========================================================================

  describe "#scan_task_history" do
    it "delegates to TaskAnalyzerService" do
      data = service.scan_task_history

      expect(data[:recommendations].length).to eq(1)
    end

    it "creates a completed discovery result" do
      service.scan_task_history

      result = Ai::DiscoveryResult.where(account: account, scan_type: "task_analysis").last
      expect(result.status).to eq("completed")
    end

    it "returns empty recommendations on failure" do
      allow(mock_task_analyzer).to receive(:analyze_history).and_raise(StandardError, "Analysis error")

      data = service.scan_task_history

      expect(data).to eq({ recommendations: [] })
    end

    it "records failure in discovery result when analyzer errors" do
      allow(mock_task_analyzer).to receive(:analyze_history).and_raise(StandardError, "Analysis error")

      service.scan_task_history

      result = Ai::DiscoveryResult.where(account: account, scan_type: "task_analysis").last
      expect(result.status).to eq("failed")
      expect(result.error_message).to eq("Analysis error")
    end
  end
end
