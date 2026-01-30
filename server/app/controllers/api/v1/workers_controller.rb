# frozen_string_literal: true

# Workers Controller
# Manages worker authentication tokens and permissions
class Api::V1::WorkersController < ApplicationController
  before_action -> { require_permission("system.workers.read") }, only: [ :index, :show, :test_worker, :health_check, :stats, :show_config ]
  before_action -> { require_permission("system.workers.create") }, only: [ :create ]
  before_action -> { require_permission("system.workers.update") }, only: [ :update, :regenerate_token, :suspend, :activate, :revoke, :update_config, :reset_config ]
  before_action -> { require_permission("system.workers.delete") }, only: [ :destroy ]
  before_action :set_worker, only: [ :show, :update, :destroy, :regenerate_token, :suspend, :activate, :revoke, :test_worker, :health_check, :show_config, :update_config, :reset_config ]

  # GET /api/v1/workers/stats
  # Returns aggregated statistics about worker jobs
  def stats
    begin
      # Fetch stats from worker service via HTTP API
      stats_response = fetch_worker_stats

      render_success({
        total_jobs: stats_response[:total_jobs] || 0,
        completed_jobs: stats_response[:completed_jobs] || 0,
        failed_jobs: stats_response[:failed_jobs] || 0,
        success_rate: stats_response[:success_rate] || 0,
        avg_processing_time: stats_response[:avg_processing_time] || 0,
        queue_depth: stats_response[:queue_depth] || 0,
        queues: stats_response[:queues] || {},
        workers_active: stats_response[:workers_active] || 0,
        timestamp: Time.current.iso8601
      })
    rescue StandardError => e
      Rails.logger.error("Failed to fetch worker stats: #{e.message}")
      # Return fallback stats on error
      render_success({
        total_jobs: 0,
        completed_jobs: 0,
        failed_jobs: 0,
        success_rate: 0,
        avg_processing_time: 0,
        queue_depth: 0,
        queues: {},
        workers_active: 0,
        timestamp: Time.current.iso8601,
        error: "Unable to fetch live stats from worker service"
      })
    end
  end

  # GET /api/v1/workers
  def index
    # Admin users can see all workers (including system workers)
    # Regular users can only see workers for their account
    @workers = if current_user.has_permission?("system.workers.read") || current_user.has_permission?("super_admin")
                 Worker.order(:name)
    else
                 current_account.workers.order(:name)
    end

    account_workers_count = @workers.count { |w| w.account_id.present? }
    system_workers_count = @workers.count { |w| w.account_id.nil? }

    render_success({
      workers: @workers.map { |worker| worker_summary(worker) },
      total: @workers.size,
      account_workers: account_workers_count,
      system_workers: system_workers_count
    })
  end

  # GET /api/v1/workers/:id
  def show
    # Get activity summary for the worker
    activity_summary = WorkerActivity.activity_summary(@worker, 24)
    recent_activities = @worker.worker_activities
                              .order(occurred_at: :desc)
                              .limit(10)
                              .map { |activity| activity_json(activity) }

    render_success({
      worker: worker_details(@worker),
      activity_summary: activity_summary,
      recent_activities: recent_activities
    })
  end

  # POST /api/v1/workers
  def create
    # Check usage limit before creating worker
    unless Billing::UsageLimitService.can_create_worker?(current_account)
      render_error("Worker limit reached for your current plan")
      return
    end

    @worker = Worker.create_worker!(
      name: worker_params[:name],
      description: worker_params[:description],
      roles: worker_params[:roles] || [],
      account: current_account
    )

    # Log worker creation activity
    @worker.record_activity!("service_created", {
      created_by_user_id: current_user.id,
      created_by_user_email: current_user.email,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' created successfully"
    }, status: :created)

  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # PATCH/PUT /api/v1/workers/:id
  def update
    # Update basic attributes
    @worker.update!(name: worker_update_params[:name], description: worker_update_params[:description])

    # Update roles if provided
    if worker_update_params[:roles]
      @worker.roles.clear
      failed_roles = []
      worker_update_params[:roles].each do |role_name|
        unless @worker.assign_role(role_name)
          failed_roles << role_name
        end
      end

      # If any roles failed to assign, return an error
      if failed_roles.any?
        render_validation_error("Invalid role assignments: #{failed_roles.join(', ')}. Check role compatibility with worker type.")
        return
      end
    end

    @worker.record_activity!("worker_updated", {
      updated_by_user_id: current_user.id,
      changes: @worker.previous_changes,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' updated successfully"
    })

  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # DELETE /api/v1/workers/:id
  def destroy
    worker_name = @worker.name

    @worker.record_activity!("worker_deleted", {
      deleted_by_user_id: current_user.id,
      status: "success"
    })

    @worker.destroy!

    render_success({
      message: "Worker '#{worker_name}' deleted successfully"
    })
  end

  # POST /api/v1/workers/:id/regenerate_token
  def regenerate_token
    old_token_preview = @worker.masked_token
    new_token = @worker.regenerate_token!

    @worker.record_activity!("token_regenerated", {
      regenerated_by_user_id: current_user.id,
      old_token_preview: old_token_preview,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      new_token: new_token,
      message: "Token regenerated for worker '#{@worker.name}'"
    })
  end

  # POST /api/v1/workers/:id/suspend
  def suspend
    @worker.suspend!

    @worker.record_activity!("worker_suspended", {
      suspended_by_user_id: current_user.id,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' suspended"
    })
  end

  # POST /api/v1/workers/:id/activate
  def activate
    @worker.activate!

    @worker.record_activity!("worker_activated", {
      activated_by_user_id: current_user.id,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' activated"
    })
  end

  # POST /api/v1/workers/:id/revoke
  def revoke
    @worker.revoke!

    @worker.record_activity!("worker_revoked", {
      revoked_by_user_id: current_user.id,
      status: "success"
    })

    render_success({
      worker: worker_details(@worker),
      message: "Worker '#{@worker.name}' revoked"
    })
  end

  # POST /api/v1/workers/:id/test
  def test_worker
    begin
      # Enqueue test job for the worker
      WorkerJobService.enqueue_test_worker_job(@worker.id, @worker.name)

      @worker.record_activity!("job_enqueue", {
        test_type: "connectivity_test",
        enqueued_by_user_id: current_user.id,
        status: "enqueued"
      })

      render_success({
        message: "Test job enqueued for worker '#{@worker.name}'",
        job_status: "enqueued",
        estimated_completion: (Time.current + 30.seconds).iso8601
      })

    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to enqueue test job for worker #{@worker.id}: #{e.message}"
      @worker.record_activity!("error_occurred", {
        test_type: "connectivity_test",
        enqueued_by_user_id: current_user.id,
        status: "failed",
        error: e.message
      })

      render_error("Failed to enqueue test job: #{e.message}", status: :service_unavailable)
    rescue StandardError => e
      Rails.logger.error "Unexpected error testing worker #{@worker.id}: #{e.message}"
      render_error("Failed to test worker", status: :internal_server_error)
    end
  end

  # POST /api/v1/workers/:id/test_results
  def test_results
    test_data = params[:test_results] || {}

    # Record the test completion activity
    @worker.record_activity!("test_completed", {
      test_type: test_data[:test_type] || "unknown",
      status: test_data[:status] || "unknown",
      duration_seconds: test_data[:duration_seconds],
      redis_check: test_data[:redis_check],
      backend_check: test_data[:backend_check],
      performed_by: "test_worker_job",
      timestamp: test_data[:timestamp] || Time.current.iso8601
    })

    # Update worker last_seen_at
    @worker.touch(:last_seen_at)

    render_success({
      message: "Test results recorded for worker '#{@worker.name}'",
      worker_id: @worker.id,
      test_status: test_data[:status] || "completed"
    })
  rescue StandardError => e
    render_internal_error("Failed to record test results", exception: e)
  end

  # GET /api/v1/workers/:id/current_token
  # Special endpoint to retrieve the current system worker token
  def current_token
    # Only allow for system workers and with super admin permissions
    unless @worker.system? && current_user.has_permission?("super_admin")
      render_error("Access denied - requires super admin access to system worker", status: :forbidden)
      return
    end

    # Get the current system worker token from environment
    current_token = ENV["WORKER_TOKEN"]

    unless current_token.present?
      render_error("System worker token not configured", status: :service_unavailable)
      return
    end

    # Verify this token actually works with this worker
    unless @worker.token_matches?(current_token)
      render_error("Environment token does not match worker", status: :conflict)
      return
    end

    @worker.record_activity!("token_accessed", {
      accessed_by_user_id: current_user.id,
      status: "success"
    })

    render_success({
      current_token: current_token,
      worker_id: @worker.id,
      worker_name: @worker.name,
      message: "Current system worker token retrieved"
    })
  end

  # POST /api/v1/workers/:id/health_check
  def health_check
    start_time = Time.current

    # Initialize check results - all start as pending
    checks = {
      connectivity: "pending",
      authentication: "pending",
      rate_limiting: "pending",
      monitoring: "pending"
    }
    details = []
    overall_status = "healthy"


    # Check 1: Connectivity (worker exists and is found)
    if @worker.nil?
      checks[:connectivity] = "fail"
      details << "Worker not found or inaccessible"
      overall_status = "error"
    else
      checks[:connectivity] = "pass"
      details << "Worker connectivity verified"
    end

    # Check 2: Authentication (worker status and token)
    if @worker.present? && @worker.revoked?
      checks[:authentication] = "fail"
      details << "Worker is revoked and cannot authenticate"
      overall_status = "error"
    elsif @worker.present? && @worker.suspended?
      checks[:authentication] = "fail"
      details << "Worker is suspended"
      overall_status = "warning"
    elsif @worker.present? && @worker.token_digest.blank?
      checks[:authentication] = "fail"
      details << "Worker has no authentication token"
      overall_status = "error"
    elsif @worker.present?
      checks[:authentication] = "pass"
      details << "Worker authentication status is valid"
    end

    # Check 3: Rate limiting (check recent activity)
    if @worker
      recent_requests = @worker.worker_activities.count
      if recent_requests > 10000 # Arbitrary high threshold
        checks[:rate_limiting] = "fail"
        details << "High request volume detected: #{recent_requests} total requests"
        overall_status = overall_status == "healthy" ? "warning" : overall_status
      else
        checks[:rate_limiting] = "pass"
        details << "Request volume normal: #{recent_requests} total requests"
      end
    end

    # Check 4: Monitoring (activity tracking)
    if @worker
      last_seen = @worker.last_seen_at
      if last_seen.nil?
        checks[:monitoring] = "fail"
        details << "Worker has never been seen (no activity recorded)"
        overall_status = overall_status == "healthy" ? "warning" : overall_status
      elsif last_seen < 24.hours.ago
        checks[:monitoring] = "fail"
        hours_ago = ((Time.current - last_seen) / 1.hour).round
        details << "Worker last seen #{hours_ago} hours ago"
        overall_status = overall_status == "healthy" ? "warning" : overall_status
      else
        checks[:monitoring] = "pass"
        minutes_ago = ((Time.current - last_seen) / 1.minute).round
        details << "Worker last seen #{minutes_ago} minutes ago"
      end
    end

    # Calculate response time
    response_time_ms = ((Time.current - start_time) * 1000).round

    # Log the health check activity
    @worker&.record_activity!("health_check", {
      status: overall_status,
      response_time_ms: response_time_ms,
      checks: checks,
      performed_by_user_id: current_user.id
    })

    render_success({
      status: overall_status,
      checks: checks,
      response_time_ms: response_time_ms,
      details: details
    })
  end

  # GET /api/v1/workers/:id/config
  # Returns the worker's configuration settings
  def show_config
    render_success(@worker.effective_config)
  end

  # PUT /api/v1/workers/:id/config
  # Updates the worker's configuration settings
  def update_config
    config_params = worker_config_params

    # Merge with existing config to allow partial updates
    new_config = (@worker.config || {}).deep_merge(config_params)

    @worker.update!(config: new_config)

    @worker.record_activity!("config_updated", {
      updated_by_user_id: current_user.id,
      updated_sections: config_params.keys,
      status: "success"
    })

    render_success({
      worker: worker_summary(@worker),
      config: @worker.effective_config,
      message: "Worker configuration updated successfully"
    })
  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record)
  end

  # POST /api/v1/workers/:id/config/reset
  # Resets the worker's configuration to defaults
  def reset_config
    @worker.reset_config!

    @worker.record_activity!("config_reset", {
      reset_by_user_id: current_user.id,
      status: "success"
    })

    render_success({
      worker: worker_summary(@worker),
      config: @worker.effective_config,
      message: "Worker configuration reset to defaults"
    })
  end

  private

  def set_worker
    # Admin users can access all workers (including system workers)
    # Regular users can only access workers for their account
    @worker = if current_user.has_permission?("system.workers.view") || current_user.has_permission?("super_admin")
                Worker.find(params[:id])
    else
                current_account.workers.find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    render_error("Worker not found", status: :not_found)
    throw :abort
  end

  def worker_params
    params.require(:worker).permit(:name, :description, roles: [])
  end

  def worker_update_params
    params.require(:worker).permit(:name, :description, roles: [])
  end

  def worker_config_params
    params.require(:worker_config).permit(
      security: [ :token_rotation_enabled, :token_expiry_days, :require_ip_whitelist,
                 :max_concurrent_sessions, :enforce_https, allowed_ips: [] ],
      rate_limiting: [ :enabled, :requests_per_minute, :burst_limit, :throttle_delay_ms ],
      monitoring: [ :activity_logging, :performance_tracking, :error_reporting, :metrics_retention_days ],
      notifications: [ :alert_on_failures, :alert_threshold, :notify_on_token_rotation, :notify_on_suspension ],
      operational: [ :auto_cleanup_activities, :cleanup_after_days, :enable_health_checks, :health_check_interval_minutes ]
    ).to_h.deep_stringify_keys
  end

  def ensure_admin_access
    unless current_user.has_permission?("admin") || current_user.has_permission?("super_admin")
      render_error("Admin access required", status: :forbidden)
    end
  end

  def worker_summary(worker)
    # Get roles and inherited permissions
    roles = worker.role_names || []
    permissions = worker.all_permissions || []

    {
      id: worker.id,
      name: worker.name,
      description: worker.description,
      roles: roles,  # Array of role names for editing
      permissions: permissions,  # Inherited permissions (read-only)
      status: worker.status,
      account_name: worker.account&.name || "System",
      masked_token: worker.masked_token,
      full_token_hash: worker.full_token_hash,
      request_count: worker.worker_activities.count,
      last_seen_at: worker.last_seen_at&.iso8601,
      active_recently: worker.active_in_last_hours(24),
      created_at: worker.created_at.iso8601,
      updated_at: worker.updated_at.iso8601
    }
  end

  def worker_details(worker)
    worker_summary(worker).merge({
      token: worker.token, # Only show full token in details view
      token_regenerated_at: nil # Field not implemented in current schema
    })
  end


  def activity_json(activity)
    {
      id: activity.id,
      action: activity.activity_type,
      performed_at: activity.occurred_at.iso8601,
      ip_address: activity.details["ip_address"],
      user_agent: activity.details["user_agent"],
      successful: activity.successful?,
      failed: activity.failed?,
      duration: activity.duration,
      response_status: activity.response_status,
      request_path: activity.request_path,
      error_message: activity.error_message,
      details: activity.details
    }
  end

  def fetch_worker_stats
    # Fetch Sidekiq stats from worker service
    worker_url = ENV.fetch("WORKER_URL", "http://localhost:4000")
    worker_token = Rails.application.config.worker_token

    response = Faraday.get("#{worker_url}/api/sidekiq/stats") do |req|
      req.headers["Authorization"] = "Bearer #{worker_token}"
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 5
      req.options.open_timeout = 2
    end

    if response.success?
      data = JSON.parse(response.body, symbolize_names: true)
      {
        total_jobs: data[:processed].to_i + data[:enqueued].to_i,
        completed_jobs: data[:processed].to_i,
        failed_jobs: data[:failed].to_i,
        success_rate: calculate_success_rate(data[:processed].to_i, data[:failed].to_i),
        avg_processing_time: data[:avg_processing_time].to_f,
        queue_depth: data[:enqueued].to_i,
        queues: data[:queues] || {},
        workers_active: data[:workers_size].to_i
      }
    else
      Rails.logger.warn("Worker service returned #{response.status}: #{response.body}")
      default_worker_stats
    end
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    Rails.logger.warn("Could not connect to worker service: #{e.message}")
    default_worker_stats
  end

  def default_worker_stats
    {
      total_jobs: 0,
      completed_jobs: 0,
      failed_jobs: 0,
      success_rate: 0,
      avg_processing_time: 0,
      queue_depth: 0,
      queues: {},
      workers_active: 0
    }
  end

  def calculate_success_rate(processed, failed)
    total = processed + failed
    return 0 if total.zero?

    ((processed.to_f / total) * 100).round(2)
  end
end
