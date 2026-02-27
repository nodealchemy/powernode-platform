# frozen_string_literal: true

# Stub WorkerJobService HTTP requests for tests
# Uses WebMock to intercept HTTP calls to the worker service
# Also stubs system_worker_jwt to avoid requiring a system worker DB record
RSpec.configure do |config|
  config.before(:each) do
    # Stub system_worker_jwt to avoid "No active system worker found" errors.
    # The JWT is generated before the HTTP request, so WebMock alone is insufficient.
    # Also clears thread-cached JWT to prevent stale tokens leaking between examples.
    Thread.current[:_system_worker_jwt] = nil
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-system-worker-jwt")

    # Get the worker URL from config, defaulting to localhost:4567
    worker_url = Rails.application.config.worker_url rescue 'http://localhost:4567'

    # Stub all requests to the worker service API
    stub_request(:any, /localhost:4567/).to_return(
      status: 200,
      body: { success: true, job_id: SecureRandom.uuid, message: 'Job enqueued' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    # Also stub any configured worker URL
    if worker_url.present? && !worker_url.include?('localhost:4567')
      stub_request(:any, /#{Regexp.escape(URI.parse(worker_url).host)}/).to_return(
        status: 200,
        body: { success: true, job_id: SecureRandom.uuid, message: 'Job enqueued' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end
  end
end
