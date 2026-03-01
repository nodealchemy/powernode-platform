# frozen_string_literal: true

module A2a
  module Client
    # AgentDiscovery - Discovers and fetches Agent Cards from external A2A agents
    class AgentDiscovery
      include HTTParty
      default_timeout 30

      WELL_KNOWN_PATH = "/.well-known/agent-card.json"

      class << self
        # Fetch an agent card from a URL
        def fetch_card(agent_card_url)
          url = normalize_url(agent_card_url)

          response = get(url, headers: default_headers, timeout: 10)

          if response.success?
            card = JSON.parse(response.body)
            validate_card!(card)
            { success: true, card: card }
          else
            { success: false, error: "HTTP #{response.code}: #{response.message}" }
          end
        rescue JSON::ParserError => e
          { success: false, error: "Invalid JSON: #{e.message}" }
        rescue StandardError => e
          { success: false, error: e.message }
        end

        # Discover agent at a base URL (tries well-known path)
        def discover(base_url)
          url = build_well_known_url(base_url)
          fetch_card(url)
        end

        # Health check an agent
        def health_check(agent_card_url)
          card_result = fetch_card(agent_card_url)

          return { healthy: false, error: card_result[:error] } unless card_result[:success]

          card = card_result[:card]
          a2a_url = card["url"]

          if a2a_url.present?
            ping_result = ping_a2a_endpoint(a2a_url)
            {
              healthy: ping_result[:success],
              response_time_ms: ping_result[:response_time_ms],
              card_version: card["version"],
              protocol_version: card["protocolVersion"]
            }
          else
            { healthy: true, card_version: card["version"] }
          end
        rescue StandardError => e
          { healthy: false, error: e.message }
        end

        # Bulk discover agents from a list of URLs
        def bulk_discover(urls)
          results = {}

          # Use parallel processing for efficiency
          threads = urls.map do |url|
            Thread.new { results[url] = discover(url) }
          end

          threads.each(&:join)
          results
        end

        private

        def normalize_url(url)
          uri = URI.parse(url)
          uri.to_s
        end

        def build_well_known_url(base_url)
          uri = URI.parse(base_url)
          uri.path = WELL_KNOWN_PATH
          uri.to_s
        end

        def default_headers
          {
            "Accept" => "application/json",
            "User-Agent" => "Powernode-A2A/1.0"
          }
        end

        def validate_card!(card)
          required_fields = %w[name url]
          missing = required_fields - card.keys

          if missing.any?
            raise ArgumentError, "Agent card missing required fields: #{missing.join(', ')}"
          end

          true
        end

        def ping_a2a_endpoint(url)
          start_time = Time.current

          response = get(url, headers: default_headers, timeout: 5)

          {
            success: response.success?,
            response_time_ms: ((Time.current - start_time) * 1000).round(2)
          }
        rescue StandardError
          { success: false }
        end
      end
    end
  end
end
