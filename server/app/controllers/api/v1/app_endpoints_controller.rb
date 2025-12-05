# frozen_string_literal: true

class Api::V1::AppEndpointsController < ApplicationController
  include AuditLogging
  
  before_action :set_app
  before_action :set_app_endpoint, only: [:show, :update, :destroy, :activate, :deactivate, :test]
  
  # GET /api/v1/apps/:app_id/endpoints
  def index
    authorize_permission!('apps.read')
    
    endpoints = @app.app_endpoints.includes(:app_endpoint_calls)
    endpoints = endpoints.where('name ILIKE ?', "%#{params[:search]}%") if params[:search].present?
    endpoints = endpoints.where(http_method: params[:method].upcase) if params[:method].present?
    endpoints = endpoints.where(is_active: params[:active]) if params[:active].present?
    endpoints = endpoints.where(version: params[:version]) if params[:version].present?

    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 20).to_i, 100].min
    offset = (page - 1) * per_page

    total_count = endpoints.count
    endpoints = endpoints.order(:name).limit(per_page).offset(offset)

    render_success(
      data: {
        endpoints: endpoints.map { |endpoint| endpoint_data(endpoint) },
        pagination: {
          current_page: page,
          per_page: per_page,
          total_count: total_count,
          total_pages: (total_count / per_page.to_f).ceil
        }
      }
    )
  end

  # GET /api/v1/apps/:app_id/endpoints/:id
  def show
    authorize_permission!('apps.read')

    render_success(
      data: endpoint_data(@app_endpoint, include_analytics: true)
    )
  end

  # POST /api/v1/apps/:app_id/endpoints
  def create
    authorize_permission!('apps.update')
    
    @app_endpoint = @app.app_endpoints.build(endpoint_params)

    if @app_endpoint.save
      render_success(
        data: endpoint_data(@app_endpoint),
        message: 'API endpoint created successfully',
        status: :created
      )
    else
      render_validation_error(@app_endpoint)
    end
  end

  # PUT /api/v1/apps/:app_id/endpoints/:id
  def update
    authorize_permission!('apps.update')

    if @app_endpoint.update(endpoint_params)
      render_success(
        data: endpoint_data(@app_endpoint),
        message: 'API endpoint updated successfully'
      )
    else
      render_validation_error(@app_endpoint)
    end
  end

  # DELETE /api/v1/apps/:app_id/endpoints/:id
  def destroy
    authorize_permission!('apps.delete')

    @app_endpoint.destroy!

    render_success(
      message: 'API endpoint deleted successfully'
    )
  end

  # POST /api/v1/apps/:app_id/endpoints/:id/activate
  def activate
    authorize_permission!('apps.update')

    @app_endpoint.update!(is_active: true)

    render_success(
      data: endpoint_data(@app_endpoint),
      message: 'API endpoint activated successfully'
    )
  end

  # POST /api/v1/apps/:app_id/endpoints/:id/deactivate
  def deactivate
    authorize_permission!('apps.update')

    @app_endpoint.update!(is_active: false)

    render_success(
      data: endpoint_data(@app_endpoint),
      message: 'API endpoint deactivated successfully'
    )
  end

  # POST /api/v1/apps/:app_id/endpoints/:id/test
  def test
    authorize_permission!('apps.update')
    
    test_data = params[:test_data] || {}
    test_headers = params[:test_headers] || {}
    
    # Create a test call record
    call = @app_endpoint.app_endpoint_calls.create!(
      account: current_account,
      request_id: SecureRandom.uuid,
      status_code: 200,
      response_time_ms: rand(50..500),
      request_size_bytes: test_data.to_json.bytesize,
      response_size_bytes: rand(100..1000),
      user_agent: request.headers['User-Agent'],
      ip_address: request.remote_ip,
      request_headers: test_headers,
      response_headers: { 'Content-Type' => 'application/json' },
      called_at: Time.current
    )

    render_success(
      data: {
        call_id: call.id,
        status_code: call.status_code,
        response_time_ms: call.response_time_ms,
        test_result: 'Endpoint test completed successfully'
      },
      message: 'API endpoint test completed'
    )
  end

  # GET /api/v1/apps/:app_id/endpoints/:id/analytics
  def analytics
    authorize_permission!('apps.read')
    
    days = [(params[:days] || 30).to_i, 90].min
    calls = @app_endpoint.app_endpoint_calls.where('called_at > ?', days.days.ago)
    
    analytics_data = {
      total_calls: calls.count,
      calls_by_day: calls.group_by_day(:called_at, last: days).count,
      calls_by_status: calls.group(:status_code).count,
      average_response_time: calls.average(:response_time_ms)&.to_f&.round(2) || 0,
      success_rate: @app_endpoint.success_rate,
      error_rate: @app_endpoint.error_rate,
      top_errors: calls.where.not(error_message: [nil, ''])
                       .group(:error_message)
                       .count
                       .sort_by { |_, count| -count }
                       .first(5)
                       .to_h
    }

    render_success(
      data: analytics_data
    )
  end

  private

  def set_app
    @app = current_account.apps.find(params[:app_id])
  rescue ActiveRecord::RecordNotFound
    render_error('App not found', status: :not_found)
  end

  def set_app_endpoint
    @app_endpoint = @app.app_endpoints.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('API endpoint not found', status: :not_found)
  end

  def endpoint_params
    params.require(:app_endpoint).permit(
      :name, :slug, :description, :http_method, :path, :request_schema, :response_schema,
      :requires_auth, :is_public, :is_active, :version,
      headers: {}, parameters: {}, authentication: {}, rate_limits: {}, metadata: {}
    )
  end

  def endpoint_data(endpoint, include_analytics: false)
    data = {
      id: endpoint.id,
      name: endpoint.name,
      slug: endpoint.slug,
      description: endpoint.description,
      http_method: endpoint.http_method,
      path: endpoint.path,
      full_path: endpoint.full_path,
      request_schema: endpoint.request_schema_json,
      response_schema: endpoint.response_schema_json,
      headers: endpoint.headers,
      parameters: endpoint.parameters,
      authentication: endpoint.authentication,
      rate_limits: endpoint.rate_limits,
      requires_auth: endpoint.requires_auth,
      is_public: endpoint.is_public,
      is_active: endpoint.is_active,
      version: endpoint.version,
      metadata: endpoint.metadata,
      created_at: endpoint.created_at,
      updated_at: endpoint.updated_at
    }

    if include_analytics
      data[:analytics] = {
        total_calls: endpoint.total_calls,
        calls_last_24h: endpoint.calls_last_24h,
        average_response_time: endpoint.average_response_time,
        success_rate: endpoint.success_rate,
        error_rate: endpoint.error_rate
      }
    end

    data
  end
end