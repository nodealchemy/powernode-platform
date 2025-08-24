# frozen_string_literal: true

# Primary Service Authentication Service
# Manages authentication using the primary service token for an account
class PrimaryServiceAuth
  CACHE_TTL = 300 # 5 minutes

  def self.instance
    @instance ||= new
  end

  def initialize
    @cache = {}
    @mutex = Mutex.new
  end

  # Get the primary service token for an account
  def get_primary_service_token(account_id = nil)
    return PowernodeWorker.application.config.service_token unless account_id

    @mutex.synchronize do
      cache_key = "primary_service_#{account_id}"
      cached = @cache[cache_key]

      # Return cached token if valid and not expired
      if cached && cached[:expires_at] > Time.current
        return cached[:token]
      end

      # Fetch fresh token from backend
      token = fetch_primary_service_token(account_id)
      
      # Cache the token
      @cache[cache_key] = {
        token: token,
        expires_at: Time.current + CACHE_TTL
      }

      token
    end
  end

  # Clear cache for specific account or all accounts
  def clear_cache(account_id = nil)
    @mutex.synchronize do
      if account_id
        @cache.delete("primary_service_#{account_id}")
      else
        @cache.clear
      end
    end
  end

  # Create an API client instance using primary service authentication
  def create_api_client(account_id = nil)
    token = get_primary_service_token(account_id)
    ApiClient.new(service_token: token)
  end

  private

  def fetch_primary_service_token(account_id)
    # Use the default service token to fetch primary service info
    client = ApiClient.new

    begin
      # Get account details which includes primary service info
      account_data = client.get("/api/v1/internal/accounts/#{account_id}")
      
      if account_data&.dig(:account, :primary_service_token)
        return account_data[:account][:primary_service_token]
      end

      # Fallback: Get the first active service for the account
      services_data = client.get("/api/v1/admin/services", { account_id: account_id })
      
      if services_data&.dig(:services)&.any?
        # Find primary service or use first active service
        primary_service = services_data[:services].find { |s| s[:primary] }
        primary_service ||= services_data[:services].find { |s| s[:status] == 'active' }
        
        if primary_service&.dig(:token)
          return primary_service[:token]
        end
      end

      PowernodeWorker.application.logger.warn "No primary service found for account #{account_id}, using default service token"
      PowernodeWorker.application.config.service_token

    rescue ApiClient::ApiError => e
      PowernodeWorker.application.logger.error "Failed to fetch primary service token for account #{account_id}: #{e.message}"
      PowernodeWorker.application.config.service_token
    end
  end
end