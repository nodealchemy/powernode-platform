# frozen_string_literal: true

# Stub WorkerJobService HTTP requests for tests
# Uses WebMock to intercept HTTP calls to the worker service
RSpec.configure do |config|
  config.before(:each) do
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
