# Service-to-service authentication controller
# Provides token verification endpoints for internal services like the worker
class Api::V1::ServiceController < ApplicationController
  skip_before_action :authenticate_request, only: [:verify, :health]
  
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
    
    # Verify token matches expected service token
    expected_token = Rails.application.credentials.worker_service_token ||
                     ENV['WORKER_SERVICE_TOKEN'] ||
                     'test-service-token-123' # Development fallback
    
    if token == expected_token
      render json: {
        valid: true,
        service: 'worker',
        verified_at: Time.current.iso8601
      }, status: 200
    else
      Rails.logger.warn "Service token verification failed: token mismatch"
      render json: { valid: false, error: 'Invalid service token' }, status: 401
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