# frozen_string_literal: true

# API Response Concern
# Provides standardized JSON response methods for API controllers
# Ensures consistent response format: {success: boolean, data: object, error?: string}
module ApiResponse
  extend ActiveSupport::Concern

  # Standard success response with data
  # @param positional_data [Object] The data to return (positional for backward compat)
  # @param data [Object] The data to return (keyword argument)
  # @param status [Symbol] HTTP status code (default: :ok)
  # @param meta [Hash] Optional metadata (pagination, etc.)
  # @param message [String] Optional message for simple success responses
  # @param extra_data [Hash] Additional keyword arguments treated as data fields
  def render_success(positional_data = nil, status: :ok, meta: nil, message: nil, data: nil, **extra_data)
    response = { success: true }

    # Determine actual data (keyword takes precedence, then positional, then extra_data)
    actual_data = if !data.nil?
                    data
    elsif positional_data.present? || positional_data.is_a?(Array)
                    positional_data
    elsif extra_data.present?
                    extra_data
    end

    # Support message-only responses: render_success(message: "Done")
    if actual_data.nil? && message.present?
      response[:data] = { message: message }
    elsif actual_data.is_a?(Array) || actual_data.present?
      # Always include arrays in response, even if empty (e.g., [] for empty lists)
      response[:data] = sanitize_for_json(actual_data)
    end

    response[:meta] = sanitize_for_json(meta) if meta.present?
    response[:message] = message if message.present?

    render json: response, status: status
  end

  # Standard error response
  # @param message [String] Error message for client
  # @param positional_status [Symbol] HTTP status code (positional for backward compat)
  # @param status [Symbol] HTTP status code (default: :bad_request)
  # @param code [String] Optional error code for client handling
  # @param details [Hash] Optional additional error details
  def render_error(message, positional_status = nil, status: :bad_request, code: nil, details: nil)
    # Determine actual status (positional takes precedence for backward compat)
    actual_status = positional_status || status

    response = {
      success: false,
      error: message
    }
    response[:code] = code if code.present?
    response[:details] = details if details.present?

    render json: response, status: actual_status
  end

  # Validation error response (422 status)
  # @param errors [ActiveModel::Errors, Array, String] Validation errors
  def render_validation_error(errors)
    case errors
    when ActiveModel::Errors
      error_details = errors.full_messages
      message = error_details.first || "Validation failed"
    when Array
      error_details = errors
      message = errors.first || "Validation failed"
    when String
      error_details = [ errors ]
      message = errors
    else
      error_details = [ "Invalid data provided" ]
      message = "Validation failed"
    end

    render_error(
      message,
      status: :unprocessable_content,
      code: "VALIDATION_ERROR",
      details: { errors: error_details }
    )
  end

  # Not found response (404 status)
  # @param resource [String] Name of resource that wasn't found
  def render_not_found(resource = "Resource")
    render_error(
      "#{resource} not found",
      status: :not_found,
      code: "NOT_FOUND"
    )
  end

  # Unauthorized response (401 status)
  # @param message [String] Custom unauthorized message
  def render_unauthorized(message = "Authentication required")
    render_error(
      message,
      status: :unauthorized,
      code: "UNAUTHORIZED"
    )
  end

  # Forbidden response (403 status)
  # @param message [String] Custom forbidden message
  def render_forbidden(message = "Access denied")
    render_error(
      message,
      status: :forbidden,
      code: "FORBIDDEN"
    )
  end

  private

  # Sanitize data for JSON rendering by converting ActionController::Parameters
  # and ensuring all nested structures are properly converted
  def sanitize_for_json(data)
    case data
    when ActionController::Parameters
      # Convert parameters to hash for JSON serialization
      # Using to_unsafe_h as this is for output serialization, not mass assignment
      data.to_unsafe_h
    when Hash
      # Recursively sanitize hash values
      data.transform_values { |v| sanitize_for_json(v) }
    when Array
      # Recursively sanitize array elements
      data.map { |item| sanitize_for_json(item) }
    else
      # Return other types as-is (String, Numeric, nil, etc.)
      data
    end
  rescue StandardError => e
    Rails.logger.error "Failed to sanitize data for JSON: #{e.message}"
    # Return safe empty value on error
    data.is_a?(Hash) || data.is_a?(ActionController::Parameters) ? {} : nil
  end

  # Internal server error response (500 status)
  # @param message [String] Error message (generic for production)
  # @param exception [Exception] Original exception for logging
  def render_internal_error(message = "Internal server error", exception: nil)
    # Log the actual error for debugging
    if exception
      Rails.logger.error "Internal Server Error: #{exception.class} - #{exception.message}"
      Rails.logger.error exception.backtrace.join("\n") if Rails.env.development? || Rails.env.test?
    end

    # Return generic error message in production for security
    error_message = Rails.env.production? ? "Internal server error" : message

    render_error(
      error_message,
      status: :internal_server_error,
      code: "INTERNAL_ERROR"
    )
  end

  # Created response (201 status) for resource creation
  # @param data [Object] The created resource data
  # @param location [String] Optional location header for new resource
  def render_created(data = nil, location: nil)
    response.headers["Location"] = location if location.present?
    render_success(data, status: :created)
  end

  # No content response (204 status) for successful operations with no data
  def render_no_content
    head :no_content
  end

  # Paginated response helper
  # @param collection [ActiveRecord::Relation] Paginated collection
  # @param serializer [Class] Optional serializer class
  def render_paginated(collection, serializer: nil)
    data = if serializer
             collection.map { |item| serializer.new(item).as_json }
    else
             collection
    end

    meta = {
      pagination: {
        current_page: collection.current_page,
        per_page: collection.limit_value,
        total_pages: collection.total_pages,
        total_count: collection.total_count,
        next_page: collection.next_page,
        prev_page: collection.prev_page
      }
    }

    render_success(data, meta: meta)
  end

  # Bulk operation response
  # @param successful [Array] Successfully processed items
  # @param failed [Array] Failed items with error messages
  def render_bulk_response(successful = [], failed = [])
    data = {
      successful: successful,
      failed: failed,
      summary: {
        total: successful.length + failed.length,
        successful_count: successful.length,
        failed_count: failed.length
      }
    }

    status = failed.empty? ? :ok : :multi_status
    render_success(data, status: status)
  end

  # Override ApplicationController error handlers to use standardized responses
  # Note: rescue_from is processed in reverse order - last defined = highest priority
  # Define general exceptions FIRST (lowest priority) and specific exceptions LAST (highest priority)
  included do
    rescue_from StandardError do |exception|
      render_internal_error("Something went wrong", exception: exception) unless performed?
    end

    rescue_from ActiveRecord::RecordInvalid do |exception|
      render_validation_error(exception.record.errors) unless performed?
    end

    rescue_from ActiveRecord::RecordNotFound do |exception|
      render_not_found(exception.model.humanize) unless performed?
    end

    rescue_from Money::Currency::UnknownCurrency do |exception|
      render_validation_error("Invalid currency: #{exception.message}") unless performed?
    end

    rescue_from ActionController::ParameterMissing do |exception|
      render_error(exception.message, status: :bad_request, code: "PARAMETER_MISSING") unless performed?
    end

    rescue_from ActiveRecord::InvalidForeignKey do |exception|
      unless performed?
        render_error(
          "Cannot delete this record because it is referenced by other records",
          status: :unprocessable_content,
          code: "FOREIGN_KEY_VIOLATION"
        )
      end
    end
  end
end
