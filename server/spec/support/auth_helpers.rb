module AuthHelpers
  # Create traditional UserToken for testing (replaces JWT)
  def token_for(user)
    result = UserToken.create_token_for_user(user, type: 'access')
    result[:token]
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
    JSON.parse(response.body)
  end

  def expect_error_response(message, status = 400)
    expect(response).to have_http_status(status)
    expect(json_response).to include(
      'success' => false,
      'error' => message
    )
  end

  def expect_success_response(data = nil)
    expect(response).to have_http_status(200)
    response_data = json_response
    expect(response_data['success']).to be true

    if data
      expect(response_data['data']).to include(data)
    end

    response_data
  end

  # Controller test authentication helper
  def sign_in_as_user(user)
    request.headers['Authorization'] = "Bearer #{token_for(user)}"
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :controller
end
