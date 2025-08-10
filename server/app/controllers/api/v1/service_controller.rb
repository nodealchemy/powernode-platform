# Service-to-service authentication controller
# Provides token verification endpoints for internal services like the worker
class Api::V1::ServiceController < ApplicationController
  skip_before_action :authenticate_request, only: [:verify, :health, :authenticate_user, :verify_session]
  
  # POST /api/v1/service/authenticate_user
  # Authenticate a user for worker web access - email/password based
  def authenticate_user
    # Extract service token from Authorization header to identify the worker service
    auth_header = request.headers['Authorization']
    
    unless auth_header&.start_with?('Bearer ')
      render json: { valid: false, error: 'Missing service token' }, status: 401
      return
    end
    
    service_token = auth_header.sub(/^Bearer /, '')
    service = Service.authenticate(service_token)
    
    unless service
      render json: { valid: false, error: 'Invalid service token' }, status: 401
      return
    end
    
    # Extract user credentials from request body
    email = params[:email]&.strip&.downcase
    password = params[:password]
    
    unless email.present? && password.present?
      render json: { valid: false, error: 'Email and password required' }, status: 400
      return
    end
    
    # Find and authenticate user
    user = User.find_by(email: email)
    
    unless user&.authenticate(password)
      Rails.logger.warn "User authentication failed for email: #{email}"
      render json: { valid: false, error: 'Invalid email or password' }, status: 401
      return
    end
    
    # Check if user belongs to the same account as the service
    unless user.account_id == service.account_id
      Rails.logger.warn "User #{email} attempted access to worker for different account"
      render json: { valid: false, error: 'Access denied: user not associated with this service' }, status: 403
      return
    end
    
    # Verify user email is confirmed
    unless user.email_verified?
      render json: { valid: false, error: 'Email verification required' }, status: 403
      return
    end
    
    # Check if user account is active
    unless user.account.active?
      render json: { valid: false, error: 'Account suspended' }, status: 403
      return
    end
    
    # Record the authentication activity
    service.record_activity!('web_interface_access', {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      user_id: user.id,
      user_email: user.email,
      status: 'success'
    })
    
    # Generate a session token for the user (JWT with short expiration)
    session_payload = {
      user_id: user.id,
      account_id: user.account_id,
      service_id: service.id,
      exp: 8.hours.from_now.to_i,
      iat: Time.current.to_i
    }
    
    session_token = JWT.encode(session_payload, Rails.application.secret_key_base, 'HS256')
    
    render json: {
      valid: true,
      user_id: user.id,
      user_email: user.email,
      account_id: user.account_id,
      service_name: service.name,
      session_token: session_token,
      expires_at: 8.hours.from_now.iso8601
    }, status: 200
  rescue StandardError => e
    Rails.logger.error "User authentication error: #{e.message}"
    render json: { valid: false, error: 'Authentication failed' }, status: 500
  end

  # POST /api/v1/service/verify_session
  # Verify a user session token for worker web access
  def verify_session
    # Extract service token from Authorization header to verify the requesting service
    auth_header = request.headers['Authorization']
    
    unless auth_header&.start_with?('Bearer ')
      render json: { valid: false, error: 'Missing service token' }, status: 401
      return
    end
    
    service_token = auth_header.sub(/^Bearer /, '')
    service = Service.authenticate(service_token)
    
    unless service
      render json: { valid: false, error: 'Invalid service token' }, status: 401
      return
    end
    
    # Extract session token from request
    session_token = params[:session_token]
    
    unless session_token.present?
      render json: { valid: false, error: 'Session token required' }, status: 400
      return
    end
    
    # Verify and decode the session token
    begin
      decoded_token = JWT.decode(session_token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
      payload = decoded_token[0]
      
      # Verify the session belongs to the same service
      unless payload['service_id'] == service.id
        render json: { valid: false, error: 'Session not valid for this service' }, status: 403
        return
      end
      
      # Find the user and verify they still exist and are active
      user = User.find_by(id: payload['user_id'])
      
      unless user&.email_verified? && user.account.active?
        render json: { valid: false, error: 'User account no longer valid' }, status: 403
        return
      end
      
      render json: {
        valid: true,
        user_id: user.id,
        user_email: user.email,
        account_id: user.account_id,
        expires_at: Time.at(payload['exp']).iso8601
      }, status: 200
      
    rescue JWT::ExpiredSignature
      render json: { valid: false, error: 'Session expired' }, status: 401
    rescue JWT::DecodeError
      render json: { valid: false, error: 'Invalid session token' }, status: 401
    end
    
  rescue StandardError => e
    Rails.logger.error "Session verification error: #{e.message}"
    render json: { valid: false, error: 'Session verification failed' }, status: 500
  end

  # POST /api/v1/service/verify
  # GET /api/v1/service/verify
  def verify
    # Extract token from Authorization header
    auth_header = request.headers['Authorization']
    
    unless auth_header&.start_with?('Bearer ')
      render json: { valid: false, error: 'Missing or invalid Authorization header' }, status: 401
      return
    end
    
    token = auth_header.sub(/^Bearer /, '')
    
    # Try to authenticate with new Service model first
    service = Service.authenticate(token)
    
    if service
      # Record the authentication activity
      service.record_activity!('authentication', {
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        request_path: request.path,
        status: 'success'
      })
      
      render json: {
        valid: true,
        service_id: service.id,
        service_name: service.name,
        permissions: service.permissions,
        account_id: service.account_id,
        verified_at: Time.current.iso8601
      }, status: 200
    else
      # Fall back to legacy service token for backward compatibility
      expected_token = Rails.application.credentials.worker_service_token ||
                       ENV['WORKER_SERVICE_TOKEN'] ||
                       'test-service-token-123' # Development fallback
      
      if token == expected_token
        render json: {
          valid: true,
          service: 'worker',
          legacy_token: true,
          verified_at: Time.current.iso8601,
          warning: 'Using legacy service token. Please migrate to Service-based authentication.'
        }, status: 200
      else
        Rails.logger.warn "Service token verification failed: no matching service found"
        render json: { valid: false, error: 'Invalid service token' }, status: 401
      end
    end
  rescue StandardError => e
    Rails.logger.error "Service token verification error: #{e.message}"
    render json: { valid: false, error: 'Token verification failed' }, status: 500
  end
  
  # GET /api/v1/service/health
  # Health check endpoint for service-to-service communication
  def health
    render json: {
      status: 'ok',
      service: 'powernode-api',
      timestamp: Time.current.iso8601,
      version: '1.0.0'
    }, status: 200
  rescue StandardError => e
    Rails.logger.error "Service health check error: #{e.message}"
    render json: { status: 'error', error: e.message }, status: 500
  end
end