# frozen_string_literal: true

module AuthHelpers
  # Create JWT token for testing with proper payload structure
  def token_for(user)
    # Reload user to ensure role associations are loaded (important for users created with permissions: [] option)
    user.reload if user.persisted?

    # Build payload with all required fields for authentication
    payload = {
      sub: user.id,
      account_id: user.account_id,
      email: user.email,
      type: 'access',
      permissions: user.permission_names, # Include permissions for faster checks
      version: Security::JwtService::CURRENT_TOKEN_VERSION
    }

    Security::JwtService.encode(payload)
  end

  # Legacy method name for backward compatibility
  def jwt_token_for(user)
    token_for(user)
  end

  def auth_headers_for(user)
    {
      'Authorization' => "Bearer #{token_for(user)}",
      'Content-Type' => 'application/json'
    }
  end

  def json_response
    # Return the full response including success/error wrapper
    JSON.parse(response.body)
  end

  def json_response_data
    # Helper to get just the data portion for convenience
    parsed = json_response
    if parsed.is_a?(Hash) && parsed.key?('success') && parsed.key?('data')
      parsed['data']
    else
      parsed
    end
  end

  def json_response_full
    # Alias for clarity - returns full response
    json_response
  end

  def expect_error_response(message = nil, status = nil)
    if status
      expect(response).to have_http_status(status)
    else
      expect(response.status).to be >= 400
    end
    expect(json_response['success']).to eq(false)
    expect(json_response['error']).to include(message) if message
  end

  def expect_success_response(data = nil)
    # Accept any 2xx success status (200 OK, 201 Created, 202 Accepted, etc.)
    expect(response).to have_http_status(:success)
    response_data = json_response
    expect(response_data['success']).to be true

    if data
      expect(response_data['data']).to include(data)
    end

    response_data
  end

  # Controller test authentication helper
  def sign_in_as_user(user)
    # For controller tests, use @request.env['HTTP_AUTHORIZATION']
    # For request tests, use request.headers
    if defined?(@request)
      @request.env['HTTP_AUTHORIZATION'] = "Bearer #{token_for(user)}"
    else
      request.headers['Authorization'] = "Bearer #{token_for(user)}"
    end
  end

  # Alias for convenience
  alias_method :sign_in, :sign_in_as_user
  alias_method :sign_in_user, :sign_in_as_user
  alias_method :auth_headers, :auth_headers_for

  # Generate JWT service token for internal API authentication (worker service)
  # InternalBaseController validates JWT with type: "worker", sub: worker_id
  def service_token
    @_service_worker ||= FactoryBot.create(:worker, account: FactoryBot.create(:account))
    Security::JwtService.encode(
      { type: "worker", sub: @_service_worker.id },
      5.minutes.from_now
    )
  end

  # Set service auth headers for internal API requests
  def set_service_auth_headers
    if defined?(@request)
      @request.headers['Authorization'] = "Bearer #{service_token}"
    else
      request.headers['Authorization'] = "Bearer #{service_token}"
    end
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :controller
end
