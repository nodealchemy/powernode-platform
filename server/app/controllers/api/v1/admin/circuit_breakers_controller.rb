# frozen_string_literal: true

class Api::V1::Admin::CircuitBreakersController < ApplicationController
  include ApiResponse

  before_action :authenticate_request
  before_action :require_read_permission, only: [:index, :show, :health, :events]
  before_action :require_write_permission, only: [:create, :update, :destroy, :reset]
  before_action :set_circuit_breaker, only: [:show, :update, :destroy, :reset, :health, :events]

  # GET /api/v1/admin/circuit_breakers
  def index
    breakers = CircuitBreaker.all.order(created_at: :desc)

    # Filter by service if provided
    breakers = breakers.for_service(params[:service]) if params[:service].present?

    # Filter by state if provided
    breakers = breakers.where(state: params[:state]) if params[:state].present?

    # Filter by health status
    case params[:health_status]
    when 'healthy'
      breakers = breakers.healthy
    when 'unhealthy'
      breakers = breakers.unhealthy
    end

    render_success({
      circuit_breakers: breakers.map { |cb| serialize_circuit_breaker(cb) },
      meta: {
        total: breakers.count,
        healthy_count: CircuitBreaker.healthy.count,
        unhealthy_count: CircuitBreaker.unhealthy.count
      }
    })
  rescue => e
    Rails.logger.error "Failed to list circuit breakers: #{e.message}"
    render_error('Failed to list circuit breakers', status: :internal_server_error)
  end

  # GET /api/v1/admin/circuit_breakers/:id
  def show
    render_success({
      circuit_breaker: serialize_circuit_breaker(@circuit_breaker, include_events: true)
    })
  rescue => e
    Rails.logger.error "Failed to get circuit breaker: #{e.message}"
    render_error('Failed to get circuit breaker', status: :internal_server_error)
  end

  # POST /api/v1/admin/circuit_breakers
  def create
    breaker = CircuitBreaker.new(circuit_breaker_params)

    if breaker.save
      render_success({
        circuit_breaker: serialize_circuit_breaker(breaker),
        message: 'Circuit breaker created successfully'
      }, status: :created)
    else
      render_validation_error(breaker.errors)
    end
  rescue => e
    Rails.logger.error "Failed to create circuit breaker: #{e.message}"
    render_error('Failed to create circuit breaker', status: :internal_server_error)
  end

  # PATCH/PUT /api/v1/admin/circuit_breakers/:id
  def update
    if @circuit_breaker.update(circuit_breaker_params)
      render_success({
        circuit_breaker: serialize_circuit_breaker(@circuit_breaker),
        message: 'Circuit breaker updated successfully'
      })
    else
      render_validation_error(@circuit_breaker.errors)
    end
  rescue => e
    Rails.logger.error "Failed to update circuit breaker: #{e.message}"
    render_error('Failed to update circuit breaker', status: :internal_server_error)
  end

  # DELETE /api/v1/admin/circuit_breakers/:id
  def destroy
    @circuit_breaker.destroy!

    render_success({
      message: 'Circuit breaker deleted successfully'
    })
  rescue => e
    Rails.logger.error "Failed to delete circuit breaker: #{e.message}"
    render_error('Failed to delete circuit breaker', status: :internal_server_error)
  end

  # POST /api/v1/admin/circuit_breakers/:id/reset
  def reset
    @circuit_breaker.reset!

    render_success({
      circuit_breaker: serialize_circuit_breaker(@circuit_breaker),
      message: 'Circuit breaker reset successfully'
    })
  rescue => e
    Rails.logger.error "Failed to reset circuit breaker: #{e.message}"
    render_error('Failed to reset circuit breaker', status: :internal_server_error)
  end

  # GET /api/v1/admin/circuit_breakers/:id/health
  def health
    metrics = @circuit_breaker.health_metrics

    render_success({
      circuit_breaker_id: @circuit_breaker.id,
      health_metrics: metrics
    })
  rescue => e
    Rails.logger.error "Failed to get health metrics: #{e.message}"
    render_error('Failed to get health metrics', status: :internal_server_error)
  end

  # GET /api/v1/admin/circuit_breakers/:id/events
  def events
    limit = params[:limit]&.to_i || 50
    events = @circuit_breaker.recent_events(limit)

    render_success({
      circuit_breaker_id: @circuit_breaker.id,
      events: events.map { |event| serialize_event(event) },
      meta: {
        count: events.count,
        limit: limit
      }
    })
  rescue => e
    Rails.logger.error "Failed to get circuit breaker events: #{e.message}"
    render_error('Failed to get circuit breaker events', status: :internal_server_error)
  end

  private

  def set_circuit_breaker
    @circuit_breaker = CircuitBreaker.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('Circuit breaker not found', status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?('admin.circuit_breakers.read')
      render_error('Insufficient permissions to view circuit breakers', status: :forbidden)
    end
  end

  def require_write_permission
    unless current_user.has_permission?('admin.circuit_breakers.write')
      render_error('Insufficient permissions to manage circuit breakers', status: :forbidden)
    end
  end

  def circuit_breaker_params
    params.require(:circuit_breaker).permit(
      :name,
      :service,
      :failure_threshold,
      :success_threshold,
      :timeout_seconds,
      :reset_timeout_seconds,
      configuration: {}
    )
  end

  def serialize_circuit_breaker(breaker, include_events: false)
    result = {
      id: breaker.id,
      name: breaker.name,
      service: breaker.service,
      state: breaker.state,
      failure_count: breaker.failure_count,
      success_count: breaker.success_count,
      failure_threshold: breaker.failure_threshold,
      success_threshold: breaker.success_threshold,
      timeout_seconds: breaker.timeout_seconds,
      reset_timeout_seconds: breaker.reset_timeout_seconds,
      last_failure_at: breaker.last_failure_at,
      last_success_at: breaker.last_success_at,
      configuration: breaker.configuration,
      created_at: breaker.created_at,
      updated_at: breaker.updated_at
    }

    if include_events
      result[:recent_events] = breaker.recent_events(10).map { |event| serialize_event(event) }
    end

    result
  end

  def serialize_event(event)
    {
      id: event.id,
      event_type: event.event_type,
      duration_ms: event.duration_ms,
      error_message: event.error_message,
      metadata: event.metadata,
      created_at: event.created_at
    }
  end
end
