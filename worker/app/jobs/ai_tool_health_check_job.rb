# frozen_string_literal: true

class AiToolHealthCheckJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  HEALTH_CHECK_TIMEOUT = 10

  def execute(params = {})
    action = params["action"] || "check_all"
    account_id = params["account_id"]

    case action
    when "check_all"
      check_all_tools
    when "check_account"
      check_account_tools(account_id) if account_id
    else
      log_info("Unknown action: #{action}")
    end
  end

  private

  def check_all_tools
    log_info("Starting tool health checks")

    servers = fetch_mcp_servers
    healthy = 0
    unhealthy = 0

    servers.each do |server|
      status = check_server_health(server["id"])
      if status
        healthy += 1
      else
        unhealthy += 1
      end
    rescue StandardError => e
      log_error("Health check failed for server #{server['id']}: #{e.message}")
      unhealthy += 1
    end

    log_info("Tool health check complete: #{healthy} healthy, #{unhealthy} unhealthy")
    report_health_summary(healthy, unhealthy)
  end

  def check_account_tools(account_id)
    log_info("Checking tools for account #{account_id}")

    servers = fetch_mcp_servers(account_id: account_id)
    servers.each do |server|
      check_server_health(server["id"])
    rescue StandardError => e
      log_error("Health check failed for server #{server['id']}: #{e.message}")
    end
  end

  def check_server_health(server_id)
    with_backend_api_circuit_breaker do
      response = backend_api_client.post(
        "/api/v1/internal/mcp/servers/#{server_id}/health_check",
        { timeout: HEALTH_CHECK_TIMEOUT }
      )

      if response.success?
        body = JSON.parse(response.body)
        body["healthy"]
      else
        log_error("Health check API failed for server #{server_id}: #{response.status}")
        false
      end
    end
  end

  def fetch_mcp_servers(account_id: nil)
    with_backend_api_circuit_breaker do
      path = "/api/v1/internal/mcp/servers"
      path += "?account_id=#{account_id}" if account_id

      response = backend_api_client.get(path)
      return [] unless response.success?

      JSON.parse(response.body)["servers"] || []
    end
  rescue StandardError => e
    log_error("Failed to fetch MCP servers: #{e.message}")
    []
  end

  def report_health_summary(healthy, unhealthy)
    with_backend_api_circuit_breaker do
      backend_api_client.post(
        "/api/v1/internal/ai/monitoring/tool_health",
        {
          healthy_count: healthy,
          unhealthy_count: unhealthy,
          checked_at: Time.current.iso8601
        }
      )
    end
  rescue StandardError => e
    log_error("Failed to report health summary: #{e.message}")
  end
end
