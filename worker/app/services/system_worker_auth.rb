# frozen_string_literal: true

require_relative 'backend_api_client'

# System Worker Authentication Service
# Worker → platform calls authenticate via mTLS. The worker's client cert
# is loaded from disk by WorkerCertManager and presented at TLS handshake
# time; the platform's reverse proxy verifies the chain and forwards the
# CN. This wrapper just constructs an API client; all auth wiring lives in
# BackendApiClient + WorkerCertManager.
class SystemWorkerAuth
  def self.instance
    @instance ||= new
  end

  def create_api_client(_account_id = nil)
    BackendApiClient.new
  end
end
