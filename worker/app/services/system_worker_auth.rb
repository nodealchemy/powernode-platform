# frozen_string_literal: true

require_relative 'backend_api_client'

# System Worker Authentication Service
# Manages authentication using the system worker token for an account
class SystemWorkerAuth
  CACHE_TTL = 300 # 5 minutes

  def self.instance
    @instance ||= new
  end

  def initialize
    @cache = {}
    @mutex = Mutex.new
  end

  # Get the system worker token for an account
  def get_system_worker_token(account_id = nil)
    return PowernodeWorker.application.config.worker_token unless account_id

    @mutex.synchronize do
      cache_key = "system_worker_#{account_id}"
      cached = @cache[cache_key]

      # Return cached token if valid and not expired
      if cached && cached[:expires_at] > Time.current
        return cached[:token]
      end

      # Fetch fresh token from backend
      token = fetch_system_worker_token(account_id)
      
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
        @cache.delete("system_worker_#{account_id}")
      else
        @cache.clear
      end
    end
  end

  # Create an API client instance using system worker authentication
  def create_api_client(account_id = nil)
    token = get_system_worker_token(account_id)
    BackendApiClient.new(worker_token: token)
  end

  private

  def fetch_system_worker_token(account_id)
    # Use the default worker token to fetch system worker info
    client = BackendApiClient.new

    begin
      # Get account details which includes system worker info
      account_data = client.get("/api/v1/internal/accounts/#{account_id}")
      
      if account_data&.dig(:account, :system_worker_token)
        return account_data[:account][:system_worker_token]
      end

      # Fallback: Get the first active worker for the account
      workers_data = client.get("/api/v1/admin/workers", { account_id: account_id })
      
      if workers_data&.dig(:workers)&.any?
        # Find system worker or use first active worker
        system_worker = workers_data[:workers].find { |w| w[:system] }
        system_worker ||= workers_data[:workers].find { |w| w[:status] == 'active' }
        
        if system_worker&.dig(:token)
          return system_worker[:token]
        end
      end

      PowernodeWorker.application.logger.warn "No system worker found for account #{account_id}, using default worker token"
      PowernodeWorker.application.config.worker_token

    rescue BackendApiClient::ApiError => e
      PowernodeWorker.application.logger.error "Failed to fetch system worker token for account #{account_id}: #{e.message}"
      PowernodeWorker.application.config.worker_token
    end
  end
end