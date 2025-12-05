# frozen_string_literal: true

class Api::V1::ApiKeysController < ApplicationController
  before_action :require_admin_access
  before_action :find_api_key, only: [:show, :update, :destroy, :regenerate, :toggle_status]

  # GET /api/v1/api_keys
  def index
    page = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 20).to_i, 100].min # Max 100 per page
    offset = (page - 1) * per_page
    
    api_keys_query = ApiKey.includes(:created_by, :account).order(:created_at)
    total_count = api_keys_query.count
    api_keys = api_keys_query.limit(per_page).offset(offset)
    
    total_pages = (total_count.to_f / per_page).ceil

    render_success(
      data: {
        api_keys: api_keys.map { |key| api_key_summary(key) },
        pagination: {
          current_page: page,
          per_page: per_page,
          total_pages: total_pages,
          total_count: total_count
        },
        stats: api_key_stats
      }
    )
  end

  # GET /api/v1/api_keys/:id
  def show
    render_success(
      data: detailed_api_key_data(@api_key)
    )
  end

  # POST /api/v1/api_keys
  def create
    # Check usage limit before creating API key
    unless UsageLimitService.can_create_api_key?(current_account)
      render_error('API key limit reached for your current plan')
      return
    end

    api_key = ApiKey.new(api_key_params)
    api_key.created_by = current_user
    api_key.account = current_user.account unless current_user.has_permission?('admin.access')

    if api_key.save
      # Log API key creation
      log_api_key_action('api_key_created', api_key)

      render_success(
        message: 'API key created successfully',
        data: detailed_api_key_data(api_key).merge({
          key_value: api_key.key_value # Only show full key on creation
        }),
        status: :created
      )
    else
      render_validation_error(api_key)
    end
  end

  # PUT /api/v1/api_keys/:id
  def update
    if @api_key.update(api_key_update_params)
      log_api_key_action('api_key_updated', @api_key)

      render_success(
        message: 'API key updated successfully',
        data: detailed_api_key_data(@api_key)
      )
    else
      render_validation_error(@api_key)
    end
  end

  # DELETE /api/v1/api_keys/:id
  def destroy
    api_key_data = api_key_summary(@api_key)
    
    if @api_key.destroy
      log_api_key_action('api_key_deleted', @api_key, api_key_data)

      render_success(
        message: 'API key deleted successfully'
      )
    else
      render_validation_error(@api_key)
    end
  end

  # POST /api/v1/api_keys/:id/regenerate
  def regenerate
    old_key_preview = @api_key.masked_key
    
    if @api_key.regenerate_key!
      log_api_key_action('api_key_regenerated', @api_key, {
        old_key_preview: old_key_preview
      })

      render_success(
        message: 'API key regenerated successfully',
        data: detailed_api_key_data(@api_key).merge({
          key_value: @api_key.key_value # Only show full key on regeneration
        })
      )
    else
      render_validation_error(@api_key)
    end
  end

  # POST /api/v1/api_keys/:id/toggle_status
  def toggle_status
    new_status = @api_key.active? ? 'revoked' : 'active'
    
    if @api_key.update(status: new_status)
      log_api_key_action('api_key_status_changed', @api_key, {
        old_status: @api_key.status_was,
        new_status: new_status
      })

      render_success(
        message: "API key #{new_status == 'active' ? 'activated' : 'revoked'}",
        data: api_key_summary(@api_key)
      )
    else
      render_validation_error(@api_key)
    end
  end

  # GET /api/v1/api_keys/usage
  def usage_stats
    api_key_id = params[:api_key_id]
    
    usage_query = ApiKeyUsage.includes(:api_key)
    usage_query = usage_query.where(api_key_id: api_key_id) if api_key_id.present?
    
    date_range = parse_date_range
    usage_query = usage_query.where(created_at: date_range) if date_range
    
    usage_stats = usage_query.group(:api_key_id)
                            .group_by_day(:created_at)
                            .sum(:request_count)

    render_success(
      data: {
        usage_stats: usage_stats,
        summary: {
          total_requests: usage_query.sum(:request_count),
          unique_api_keys: usage_query.distinct.count(:api_key_id),
          date_range: {
            from: date_range&.begin&.iso8601,
            to: date_range&.end&.iso8601
          }
        }
      }
    )
  end

  # GET /api/v1/api_keys/scopes
  def available_scopes
    render_success(
      data: {
        scopes: ApiKey.available_scopes,
        scope_descriptions: ApiKey.scope_descriptions
      }
    )
  end

  # POST /api/v1/api_keys/validate
  def validate_key
    key_value = params[:key]
    return render_error('API key required', status: :bad_request) unless key_value.present?

    api_key = ApiKey.find_by(key_hash: ApiKey.hash_key(key_value))

    if api_key&.valid_for_use?
      render_success(
        data: {
          valid: true,
          id: api_key.id,
          name: api_key.name,
          scopes: api_key.scopes,
          account_id: api_key.account_id,
          expires_at: api_key.expires_at&.iso8601
        }
      )
    else
      render_success(
        data: {
          valid: false,
          reason: api_key ? api_key.invalid_reason : 'API key not found'
        }
      )
    end
  end

  private

  def require_admin_access
    unless current_user.has_permission?('account.manage') || current_user.has_permission?('admin.access')
      render_error("Access denied: Admin privileges required", status: :forbidden)
    end
  end

  def find_api_key
    @api_key = ApiKey.find(params[:id])
    
    # Non-admin users can only manage their account's API keys
    unless current_user.has_permission?('admin.access') || @api_key.account == current_user.account
      render_error('Access denied: You can only manage your account\'s API keys', status: :forbidden)
      return false
    end

    true
  rescue ActiveRecord::RecordNotFound
    render_error('API key not found', status: :not_found)
    false
  end

  def api_key_params
    params.require(:api_key).permit(:name, :description, :expires_at, scopes: [])
  end

  def api_key_update_params
    params.require(:api_key).permit(:name, :description, :expires_at, scopes: [])
  end

  def api_key_summary(api_key)
    {
      id: api_key.id,
      name: api_key.name,
      description: api_key.description,
      masked_key: api_key.masked_key,
      status: api_key.status,
      scopes: api_key.scopes || [],
      expires_at: api_key.expires_at&.iso8601,
      last_used_at: api_key.last_used_at&.iso8601,
      usage_count: api_key.usage_count || 0,
      created_at: api_key.created_at.iso8601,
      created_by: api_key.created_by ? {
        id: api_key.created_by.id,
        email: api_key.created_by.email
      } : nil,
      account: api_key.account ? {
        id: api_key.account.id,
        name: api_key.account.name
      } : nil
    }
  end

  def detailed_api_key_data(api_key)
    api_key_summary(api_key).merge({
      rate_limit_per_hour: api_key.rate_limit_per_hour,
      rate_limit_per_day: api_key.rate_limit_per_day,
      allowed_ips: api_key.allowed_ips || [],
      recent_usage: api_key.api_key_usages
                          .order(created_at: :desc)
                          .limit(10)
                          .map { |usage| usage_summary(usage) },
      usage_stats: {
        requests_today: api_key.requests_today,
        requests_this_week: api_key.requests_this_week,
        requests_this_month: api_key.requests_this_month,
        average_requests_per_day: api_key.average_requests_per_day
      }
    })
  end

  def usage_summary(usage)
    {
      id: usage.id,
      endpoint: usage.endpoint,
      method: usage.http_method,
      status_code: usage.status_code,
      request_count: usage.request_count,
      ip_address: usage.ip_address,
      user_agent: usage.user_agent,
      created_at: usage.created_at.iso8601
    }
  end

  def api_key_stats
    {
      total_keys: ApiKey.count,
      active_keys: ApiKey.active.count,
      revoked_keys: ApiKey.revoked.count,
      expired_keys: ApiKey.expired.count,
      requests_today: ApiKeyUsage.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).sum(:request_count),
      most_used_keys: ApiKey.joins(:api_key_usages)
                           .group('api_keys.name')
                           .order('SUM(api_key_usages.request_count) DESC')
                           .limit(5)
                           .sum('api_key_usages.request_count')
    }
  end

  def parse_date_range
    return nil unless params[:date_from] || params[:date_to]
    
    start_date = params[:date_from]&.to_date&.beginning_of_day || 30.days.ago.beginning_of_day
    end_date = params[:date_to]&.to_date&.end_of_day || Time.current
    
    start_date..end_date
  end

  def log_api_key_action(action, api_key, metadata = {})
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: action,
      resource_type: 'ApiKey',
      resource_id: api_key.id,
      source: 'admin_panel',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata.merge({
        api_key_name: api_key.name,
        scopes: api_key.scopes
      })
    )
  end
end