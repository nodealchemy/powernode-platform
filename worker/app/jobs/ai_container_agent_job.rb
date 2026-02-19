# frozen_string_literal: true

# AiContainerAgentJob - Deploys and monitors containerized agent sessions on Docker Swarm
#
# Called by ContainerChatBridgeService when async deployment is needed.
# Handles the full lifecycle: provision → monitor → completion/timeout.
class AiContainerAgentJob < BaseJob
  sidekiq_options queue: "ai_agents", retry: 2, dead: true

  def execute(params)
    validate_required_params(params, "execution_id", "account_id")

    execution_id = params["execution_id"]
    account_id = params["account_id"]

    log_info("[ContainerAgent] Starting deployment",
             execution_id: execution_id, account_id: account_id)

    # Fetch container instance details from backend
    instance_data = fetch_container_instance(execution_id)

    unless instance_data
      log_error("[ContainerAgent] Container instance not found: #{execution_id}")
      return
    end

    service_spec = instance_data.dig("input_parameters", "service_spec")
    cluster_id = instance_data.dig("input_parameters", "swarm_cluster_id")

    unless service_spec && cluster_id
      log_error("[ContainerAgent] Missing service_spec or cluster_id for #{execution_id}")
      update_container_status(execution_id, "failed",
                              error: "Missing deployment configuration")
      return
    end

    # Get Swarm cluster connection details
    cluster_data = fetch_cluster_connection(cluster_id)

    unless cluster_data
      log_error("[ContainerAgent] Could not fetch cluster connection for #{cluster_id}")
      update_container_status(execution_id, "failed",
                              error: "Swarm cluster unavailable")
      return
    end

    # Deploy the service to Swarm
    deploy_to_swarm(
      execution_id: execution_id,
      service_spec: service_spec,
      cluster_data: cluster_data
    )

    log_info("[ContainerAgent] Deployment complete",
             execution_id: execution_id)
  end

  private

  def fetch_container_instance(execution_id)
    response = api_client.get("/api/v1/internal/devops/container_executions/#{execution_id}")
    response["data"]
  rescue StandardError => e
    log_error("[ContainerAgent] Failed to fetch instance", e)
    nil
  end

  def fetch_cluster_connection(cluster_id)
    response = api_client.get("/api/v1/internal/devops/swarm/clusters/#{cluster_id}/connection")
    response["data"]
  rescue StandardError => e
    log_error("[ContainerAgent] Failed to fetch cluster connection", e)
    nil
  end

  def deploy_to_swarm(execution_id:, service_spec:, cluster_data:)
    update_container_status(execution_id, "deploying")
    api_endpoint = cluster_data['api_endpoint']

    require 'net/http'

    uri = URI("#{api_endpoint}/services/create")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = service_spec.to_json

    response = http.request(request)

    if response.code.to_i.between?(200, 299)
      update_container_status(execution_id, "running")
      parsed = JSON.parse(response.body) rescue {}
      log_info("[ContainerAgent] Swarm service created",
               execution_id: execution_id, service_id: parsed['ID'])
      { service_id: parsed['ID'] }
    else
      update_container_status(execution_id, "failed",
                              error: "Swarm deploy failed: HTTP #{response.code}")
      raise "Swarm deploy failed: #{response.body}"
    end
  rescue StandardError => e
    log_error("[ContainerAgent] Swarm deployment failed", e,
              execution_id: execution_id)
    update_container_status(execution_id, "failed",
                            error: "Swarm deployment error: #{e.message}")
  end

  def update_container_status(execution_id, status, error: nil)
    payload = { status: status }
    payload[:error_message] = error if error

    api_client.post(
      "/api/v1/internal/container_executions/#{execution_id}/status",
      payload
    )
  rescue StandardError => e
    log_error("[ContainerAgent] Failed to update status", e,
              execution_id: execution_id, target_status: status)
  end
end
