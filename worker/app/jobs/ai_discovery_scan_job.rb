# frozen_string_literal: true

# AiDiscoveryScanJob - Background agent discovery scanning
# Scans MCP servers, Docker hosts, and Swarm clusters for discoverable agents and connections
class AiDiscoveryScanJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 2

  def execute(args = {})
    @account_id = args[:account_id] || args['account_id']
    @scan_type = args[:scan_type] || args['scan_type'] || 'full_scan'
    @scan_id = args[:scan_id] || args['scan_id']

    log_info "[AiDiscoveryScanJob] Starting #{@scan_type} scan: #{@scan_id} for account #{@account_id}"

    discovered = perform_scan

    report_scan_complete(discovered)

    log_info "[AiDiscoveryScanJob] Completed #{@scan_type} scan: #{@scan_id}"
    discovered
  rescue StandardError => e
    report_scan_failed(e)
    raise
  end

  private

  def perform_scan
    case @scan_type
    when 'mcp_scan'
      scan_mcp_servers
    when 'docker_scan'
      scan_docker_hosts
    when 'swarm_scan'
      scan_swarm_clusters
    when 'task_analysis'
      analyze_tasks
    when 'full_scan'
      run_full_scan
    else
      { agents: [], connections: [], tools: [], recommendations: [] }
    end
  end

  def scan_mcp_servers
    response = api_client.get("/api/v1/internal/ai/discovery/mcp_servers?account_id=#{@account_id}")
    servers = response['data'] || []

    agents = []
    tools = []
    connections = []

    servers.each do |server|
      tools_data = server['capabilities']&.dig('tools') || []
      tools_data.each do |tool|
        tools << {
          name: tool['name'],
          description: tool['description'],
          server_id: server['id'],
          server_name: server['name']
        }
      end

      connections << {
        source_type: 'McpServer',
        source_id: server['id'],
        target_type: 'Ai::Agent',
        target_id: nil,
        connection_type: 'mcp_tool_usage',
        discovered_by: 'mcp_scan'
      }
    end

    { agents: agents, connections: connections, tools: tools, recommendations: [] }
  rescue StandardError => e
    log_error "[AiDiscoveryScanJob] MCP scan error", e
    { agents: [], connections: [], tools: [], recommendations: [] }
  end

  def scan_docker_hosts
    response = api_client.get("/api/v1/internal/ai/discovery/docker_hosts?account_id=#{@account_id}")
    hosts = response['data'] || []

    agents = []
    connections = []

    hosts.each do |host|
      containers = host['containers'] || []
      containers.each do |container|
        if container['name']&.match?(/agent|ai|bot/i)
          agents << {
            name: container['name'],
            type: 'docker_container',
            host_id: host['id'],
            status: container['status'],
            discovered_by: 'docker_scan'
          }
        end
      end

      connections << {
        source_type: 'Devops::DockerHost',
        source_id: host['id'],
        connection_type: 'infrastructure',
        discovered_by: 'docker_scan'
      }
    end

    { agents: agents, connections: connections, tools: [], recommendations: [] }
  rescue StandardError => e
    log_error "[AiDiscoveryScanJob] Docker scan error", e
    { agents: [], connections: [], tools: [], recommendations: [] }
  end

  def scan_swarm_clusters
    response = api_client.get("/api/v1/internal/ai/discovery/swarm_clusters?account_id=#{@account_id}")
    clusters = response['data'] || []

    agents = []
    connections = []

    clusters.each do |cluster|
      services = cluster['services'] || []
      services.each do |service|
        if service['name']&.match?(/agent|ai|bot/i)
          agents << {
            name: service['name'],
            type: 'swarm_service',
            cluster_id: cluster['id'],
            status: service['status'],
            discovered_by: 'swarm_scan'
          }
        end
      end

      connections << {
        source_type: 'Devops::SwarmCluster',
        source_id: cluster['id'],
        connection_type: 'infrastructure',
        discovered_by: 'swarm_scan'
      }
    end

    { agents: agents, connections: connections, tools: [], recommendations: [] }
  rescue StandardError => e
    log_error "[AiDiscoveryScanJob] Swarm scan error", e
    { agents: [], connections: [], tools: [], recommendations: [] }
  end

  def analyze_tasks
    { agents: [], connections: [], tools: [], recommendations: [] }
  end

  def run_full_scan
    mcp = scan_mcp_servers
    docker = scan_docker_hosts
    swarm = scan_swarm_clusters
    tasks = analyze_tasks

    {
      agents: mcp[:agents] + docker[:agents] + swarm[:agents] + tasks[:agents],
      connections: mcp[:connections] + docker[:connections] + swarm[:connections] + tasks[:connections],
      tools: mcp[:tools] + docker[:tools] + swarm[:tools] + tasks[:tools],
      recommendations: mcp[:recommendations] + docker[:recommendations] + swarm[:recommendations] + tasks[:recommendations]
    }
  end

  def report_scan_complete(discovered)
    api_client.post(
      "/api/v1/internal/ai/discovery/#{@scan_id}/complete",
      {
        agents: discovered[:agents],
        connections: discovered[:connections],
        tools: discovered[:tools],
        recommendations: discovered[:recommendations]
      }
    )
  rescue StandardError => e
    log_error "[AiDiscoveryScanJob] Failed to report completion", e
  end

  def report_scan_failed(error)
    api_client.post(
      "/api/v1/internal/ai/discovery/#{@scan_id}/failed",
      { error_message: error.message }
    )
  rescue StandardError => e
    log_error "[AiDiscoveryScanJob] Failed to report failure", e
  end
end
