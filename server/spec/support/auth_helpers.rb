module AuthHelpers
  def jwt_token_for(user)
    # Get primary role name for backward compatibility
    primary_role = user.roles.first&.name || 'Member'
    
    payload = {
      user_id: user.id,
      account_id: user.account.id,
      email: user.email,
      role: primary_role.downcase,
      type: 'access',
      exp: 1.hour.from_now.to_i
    }

    JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
  end

  def auth_headers_for(user)
    {
      'Authorization' => "Bearer #{jwt_token_for(user)}",
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
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :controller
end
