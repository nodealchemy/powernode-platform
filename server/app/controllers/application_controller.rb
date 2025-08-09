# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Authentication

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_validation_errors
  rescue_from StandardError, with: :render_internal_error

  private

  def render_not_found(exception = nil)
    render json: {
      error: "Resource not found",
      message: exception&.message || "The requested resource could not be found"
    }, status: :not_found
  end

  def render_validation_errors(exception)
    render json: {
      error: "Validation failed",
      details: exception.record.errors.full_messages
    }, status: :unprocessable_content
  end

  def render_internal_error(exception)
    Rails.logger.error "Internal error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n") if Rails.env.development?

    render json: {
      error: "Internal server error",
      message: Rails.env.development? ? exception.message : "Something went wrong"
    }, status: :internal_server_error
  end

  def pagination_params
    {
      page: [ params[:page].to_i, 1 ].max,
      per_page: [ [ params[:per_page].to_i, 1 ].max, 100 ].min
    }
  end
end
