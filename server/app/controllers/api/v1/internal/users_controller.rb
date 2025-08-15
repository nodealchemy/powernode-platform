# frozen_string_literal: true

# Internal API controller for worker service to fetch user data
class Api::V1::Internal::UsersController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token
  
  # GET /api/v1/internal/users/:id
  def show
    user = User.find(params[:id])
    
    render json: {
      id: user.id,
      email: user.email,
      name: user.name,
      reset_token: user.instance_variable_get(:@reset_token), # Access the temporary reset token
      email_verified: user.email_verified?,
      created_at: user.created_at,
      last_login_at: user.last_login_at
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'User not found' }, status: :not_found
  end
  
  private
  
  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last
    
    unless token.present?
      render json: { error: 'Service token required' }, status: :unauthorized
      return
    end
    
    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first
      
      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render json: { error: 'Invalid service token' }, status: :unauthorized
        return
      end
      
    rescue JWT::DecodeError, JWT::ExpiredSignature
      render json: { error: 'Invalid service token' }, status: :unauthorized
    end
  end
end