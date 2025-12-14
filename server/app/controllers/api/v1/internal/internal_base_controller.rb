# frozen_string_literal: true

# Base controller for internal API endpoints accessed by worker service
class Api::V1::Internal::InternalBaseController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  private

  def authenticate_service_token
    token = request.headers["Authorization"]&.split(" ")&.last

    unless token.present?
      render_error("Service token required", status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

      unless payload["service"] == "worker" && payload["type"] == "service"
        render_error("Invalid service token", status: :unauthorized)
        nil
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error("Invalid service token", status: :unauthorized)
    end
  end
end
