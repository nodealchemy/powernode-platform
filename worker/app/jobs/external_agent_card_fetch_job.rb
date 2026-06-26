# frozen_string_literal: true

require 'net/http'
require 'uri'

# Fetches an external A2A agent card over HTTP and reports the raw outcome back
# to the server. Per the worker architecture, the worker performs network I/O
# ONLY — it does NO A2A parse/validate and NO model/DB access. The server's
# Internal::ExternalAgents#card_result endpoint parses/validates/persists.
#
# Relocated from server/app/jobs (the Rails API runs no Sidekiq and must hold no
# job classes). Pattern B: worker fetches → HTTP callback → server persists.
class ExternalAgentCardFetchJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'default', retry: 5

  # Match the server-side A2A discovery fetch timeout (seconds).
  FETCH_TIMEOUT = 10

  def execute(external_agent_id, agent_card_url)
    log_info('Fetching external agent card', external_agent_id: external_agent_id, url: agent_card_url)

    outcome = fetch_card_body(agent_card_url)

    backend_api_post(
      "/api/v1/internal/external_agents/#{external_agent_id}/card_result",
      outcome
    )
  end

  private

  # Perform a generic HTTP GET of the agent card URL. Returns the raw outcome
  # for the server to interpret (the worker stays A2A-agnostic):
  #   success: { "http_status" => Integer, "body" => String }
  #   failure: { "error" => String } — network failure / timeout / bad URL
  def fetch_card_body(agent_card_url)
    uri = URI.parse(agent_card_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = FETCH_TIMEOUT
    http.read_timeout = FETCH_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/json'
    request['User-Agent'] = 'Powernode-A2A/1.0'

    response = http.request(request)

    { 'http_status' => response.code.to_i, 'body' => response.body }
  rescue StandardError => e
    log_warn("External agent card fetch failed for #{agent_card_url}: #{e.message}")
    { 'error' => e.message }
  end
end
