# frozen_string_literal: true

class Api::V1::AuditLogsController < ApplicationController
  skip_before_action :authenticate_request, only: [:create]
  before_action -> { require_permission("audit_logs.read") }, only: [:index, :show, :stats, :security_summary, :compliance_summary, :activity_timeline, :risk_analysis]
  before_action -> { require_permission("audit_logs.export") }, only: [:export]
  before_action :authenticate_worker_or_admin, only: [:create]

  # GET /api/v1/audit_logs
  def index
    page = params[:page] || 1
    per_page = [params[:per_page]&.to_i || 50, 200].min

    logs = AuditLog.includes(:user, :account)
                   .apply_filters(audit_log_filters)
                   .order(created_at: :desc)
                   .page(page)
                   .per(per_page)

    render_success(
      data: logs.map { |log| query_service.format_log(log) },
      meta: {
        current_page: logs.current_page,
        per_page: logs.limit_value,
        total_pages: logs.total_pages,
        total: logs.total_count,
        stats: query_service.basic_stats
      }
    )
  end

  # GET /api/v1/audit_logs/:id
  def show
    log = AuditLog.includes(:user, :account).find(params[:id])
    render_success(data: query_service.format_detailed_log(log))
  rescue ActiveRecord::RecordNotFound
    render_error("Audit log not found", status: :not_found)
  end

  # GET /api/v1/audit_logs/stats
  def stats
    render_success(data: query_service.detailed_stats)
  end

  # GET /api/v1/audit_logs/security_summary
  def security_summary
    start_time = query_service.parse_time_range(params[:time_range] || "24h")
    render_success(query_service.security_summary(start_time: start_time))
  end

  # GET /api/v1/audit_logs/compliance_summary
  def compliance_summary
    start_time = query_service.parse_time_range(params[:time_range] || "30d")
    render_success(query_service.compliance_summary(start_time: start_time))
  end

  # GET /api/v1/audit_logs/activity_timeline
  def activity_timeline
    start_time = query_service.parse_time_range(params[:time_range] || "24h")
    granularity = params[:granularity] || "hour"
    render_success(query_service.activity_timeline(start_time: start_time, granularity: granularity))
  end

  # GET /api/v1/audit_logs/risk_analysis
  def risk_analysis
    start_time = query_service.parse_time_range(params[:time_range] || "7d")
    render_success(query_service.risk_analysis(start_time: start_time))
  end

  # POST /api/v1/audit_logs/export
  def export
    filters = audit_log_filters
    format = params[:format] || "csv"

    if should_use_background_export?
      job_id = AuditLogExportJob.perform_later(current_user.id, filters, format).job_id

      render_success(
        message: "Export job queued successfully",
        data: { job_id: job_id, estimated_completion: 5.minutes.from_now.iso8601 },
        status: :accepted
      )
    else
      logs = AuditLog.includes(:user, :account)
                     .apply_filters(filters)
                     .order(created_at: :desc)
                     .limit(1000)

      render_success(
        data: {
          format: format,
          content: query_service.generate_export_data(logs, format),
          filename: "audit_logs_#{Date.current.strftime('%Y%m%d')}.#{format}"
        }
      )
    end
  end

  # POST /api/v1/audit_logs
  def create
    audit_params = extract_audit_params
    return render_error("Action is required", status: :unprocessable_content) unless audit_params[:action].present?

    apply_defaults!(audit_params)
    metadata = build_metadata(audit_params)
    account = find_account

    return render_error("No account found for audit log", status: :unprocessable_content) unless account

    audit_log = AuditLog.create!(
      action: audit_params[:action],
      resource_type: audit_params[:resource_type],
      resource_id: audit_params[:resource_id],
      user: current_user,
      account: account,
      source: audit_params[:source],
      ip_address: audit_params[:ip_address],
      user_agent: audit_params[:user_agent],
      metadata: metadata
    )

    render_success(
      message: "Audit log created successfully",
      data: { id: audit_log.id, action: audit_log.action, created_at: audit_log.created_at.iso8601 },
      status: :created
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Audit log validation failed: #{e.record.errors.full_messages.join(', ')}"
    render_error("Invalid audit log data", :unprocessable_content, details: e.record.errors.full_messages)
  rescue StandardError => e
    Rails.logger.error "Failed to create audit log: #{e.message}"
    render_error("Failed to create audit log", :internal_server_error, details: e.message)
  end

  # DELETE /api/v1/audit_logs/cleanup
  def cleanup
    cutoff_date = params[:cutoff_date]&.to_date || 1.year.ago.to_date
    return render_error("Invalid cutoff date", status: :bad_request) if cutoff_date > Date.current

    deleted_count = AuditLog.where("created_at < ?", cutoff_date).delete_all

    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: "audit_log_cleanup",
      resource_type: "AuditLog",
      resource_id: "bulk_cleanup",
      source: "admin_panel",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { cutoff_date: cutoff_date.iso8601, deleted_count: deleted_count }
    )

    render_success(
      message: "Successfully deleted #{deleted_count} audit log entries",
      data: { deleted_count: deleted_count, cutoff_date: cutoff_date.iso8601 }
    )
  end

  private

  def query_service
    @query_service ||= AuditLogQueryService.new
  end

  def audit_log_filters
    {
      action: params[:action_type],
      user_email: params[:user_email],
      account_name: params[:account_name],
      resource_type: params[:resource_type],
      source: params[:source],
      ip_address: params[:ip_address],
      date_from: params[:date_from]&.to_date,
      date_to: params[:date_to]&.to_date,
      status: params[:status]
    }.compact
  end

  def should_use_background_export?
    AuditLog.apply_filters(audit_log_filters).count > 5000
  end

  def extract_audit_params
    if params[:audit_log].present?
      params[:audit_log].permit(:action, :resource_type, :resource_id, :source, :ip_address, :user_agent, details: {})
    else
      params.permit(:action, :resource_type, :resource_id, :source, :ip_address, :user_agent, details: {})
    end
  end

  def apply_defaults!(audit_params)
    audit_params[:resource_type] ||= "WorkerJob"
    audit_params[:resource_id] ||= "worker_task"
    audit_params[:source] ||= "worker"
    audit_params[:ip_address] ||= request.remote_ip
    audit_params[:user_agent] ||= request.user_agent
  end

  def build_metadata(audit_params)
    metadata = audit_params[:details] || params[:details] || {}
    metadata[:created_via] = "worker_api"
    metadata[:request_timestamp] = Time.current.iso8601
    metadata
  end

  def find_account
    current_user&.account || Account.find_by(name: "System") || Account.first
  end

  def authenticate_worker_or_admin
    return if current_user&.has_permission?("admin.access")

    auth_header = request.headers["Authorization"]
    return render_error("Missing authorization header", status: :unauthorized) unless auth_header

    token = auth_header.sub(/^Bearer /, "")
    return render_error("Missing token", status: :unauthorized) if token.blank?

    if token.starts_with?("swt_")
      worker = Worker.find_by(token: token, status: "active")
      return if worker.present?
      return render_error("Invalid worker token", status: :unauthorized)
    end

    # Try user JWT authentication first (for admin users calling create directly)
    begin
      payload = Security::JwtService.decode(token)
      if payload[:type] == "access"
        user = User.find_by(id: payload[:user_id])
        if user&.active? && user&.has_permission?("admin.access")
          @current_user = user
          @current_account = user.account
          return
        end
      end
    rescue StandardError
      # Fall through to service token validation
    end

    validate_service_token(token)
  end

  def validate_service_token(token)
    payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

    if payload["service"] == "backend" && payload["type"] == "service"
      return
    end

    render_error("Invalid service token", status: :unauthorized)
  rescue JWT::DecodeError, JWT::ExpiredSignature => e
    Rails.logger.warn "Invalid service token for audit log creation: #{e.message}"
    render_error("Invalid or expired service token", status: :unauthorized)
  end
end
