# frozen_string_literal: true

# Internal API controller for worker service to fetch account data
class Api::V1::Internal::AccountsController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token
  
  # GET /api/v1/internal/accounts/:id
  def show
    account = Account.find(params[:id])
    owner = account.owner

    render_success(
      data: {
        account: {
          id: account.id,
          name: account.name,
          billing_email: account.billing_email,
          owner_email: owner&.email,
          owner_name: owner&.name,
          plan_name: account.subscription&.plan&.name,
          status: account.subscription&.status,
          system_worker_token: account.system_worker_token,
          has_system_worker: account.has_system_worker?,
          created_at: account.created_at
        }
      }
    )
  rescue ActiveRecord::RecordNotFound
    render_error('Account not found', status: :not_found)
  end
  
  private
  
  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last
    
    unless token.present?
      render_error('Service token required', status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first

      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render_error('Invalid service token', status: :unauthorized)
        return
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid service token', status: :unauthorized)
    end
  end
end