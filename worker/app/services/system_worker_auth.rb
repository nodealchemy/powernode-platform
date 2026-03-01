# frozen_string_literal: true

require_relative 'backend_api_client'

# System Worker Authentication Service
# All authentication now uses JWT tokens via WorkerJwt.
# This service provides a convenience wrapper for creating API clients.
class SystemWorkerAuth
  def self.instance
    @instance ||= new
  end

  # Create an API client instance using JWT authentication
  def create_api_client(_account_id = nil)
    BackendApiClient.new
  end
end
