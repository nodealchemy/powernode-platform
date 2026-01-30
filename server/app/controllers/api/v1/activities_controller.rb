# frozen_string_literal: true

# Worker Activities Controller
# Manages activity tracking and viewing for workers
class Api::V1::ActivitiesController < ApplicationController
  before_action -> { require_permission("system.workers.read") }
  before_action :set_worker
  before_action :set_activity, only: [ :show ]

  # GET /api/v1/workers/:worker_id/activities
  def index
    begin
      @activities = @worker.worker_activities.order(occurred_at: :desc)

      # Apply filters
      @activities = @activities.where(activity_type: params[:action]) if params[:action].present?
      @activities = apply_status_filter(@activities, params[:status]) if params[:status].present?
      @activities = apply_date_range_filter(@activities) if params[:from] || params[:to]

      # Pagination
      page = [ params[:page]&.to_i || 1, 1 ].max
      per_page = [ [ params[:per_page]&.to_i || 20, 1 ].max, 100 ].min

      offset = (page - 1) * per_page
      total_count = @activities.count
      total_pages = (total_count.to_f / per_page).ceil

      @activities = @activities.limit(per_page).offset(offset)

      # Generate summary statistics
      summary = generate_activity_summary(@worker, @worker.worker_activities)

      render_success({
        activities: @activities.map { |activity| activity_json(activity) },
        pagination: {
          page: page,
          per_page: per_page,
          total: total_count,
          total_pages: total_pages
        },
        summary: summary,
        worker: {
          id: @worker.id,
          name: @worker.name,
          roles: @worker.role_names,
          permissions: @worker.all_permissions
        }
      })
    rescue StandardError => e
      render_internal_error("Failed to load activities", exception: e)
    end
  end

  # GET /api/v1/workers/:worker_id/activities/:id
  def show
    render_success({
      activity: activity_json(@activity),
      worker: {
        id: @worker.id,
        name: @worker.name
      }
    })
  end

  # GET /api/v1/workers/:worker_id/activities/summary
  def summary
    hours = [ params[:hours]&.to_i || 24, 1 ].max

    # Get activities within time range
    activities = @worker.worker_activities.where("occurred_at > ?", hours.hours.ago)

    # Generate hourly breakdown
    requests_by_hour = {}
    actions_breakdown = {}
    hourly_breakdown = {}

    (0...hours).each do |hour_ago|
      hour_start = hour_ago.hours.ago.beginning_of_hour
      hour_end = hour_start + 1.hour
      hour_key = hour_start.strftime("%Y-%m-%d %H:00")
      count = activities.where(occurred_at: hour_start...hour_end).count
      requests_by_hour[hour_key] = count
      hourly_breakdown[hour_key] = count
    end

    # Actions breakdown
    activities.group(:activity_type).count.each do |action, count|
      actions_breakdown[action] = count
    end

    summary_data = {
      total_requests: activities.count,
      successful_requests: activities.successful.count,
      failed_requests: activities.failed.count,
      unique_actions: activities.distinct.pluck(:activity_type),
      last_activity: activities.order(:occurred_at).last&.occurred_at&.iso8601,
      requests_by_hour: requests_by_hour,
      actions_breakdown: actions_breakdown,
      hourly_breakdown: hourly_breakdown,
      success_rate: activities.count > 0 ? (activities.successful.count.to_f / activities.count * 100).round(2) : 0
    }

    # Add average response time if available
    durations = activities.where.not("details->>'duration' IS NULL").pluck("(details->>'duration')::float")
    if durations.any?
      summary_data[:average_response_time] = (durations.sum / durations.size).round(3)
    end

    render_success({
      worker: {
        id: @worker.id,
        name: @worker.name,
        roles: @worker.role_names,
        permissions: @worker.all_permissions
      },
      time_range: {
        hours: hours,
        from: hours.hours.ago.iso8601,
        to: Time.current.iso8601
      },
      summary: summary_data
    })
  end

  # DELETE /api/v1/workers/:worker_id/activities/cleanup
  def cleanup
    days = [ params[:days]&.to_i || 30, 1 ].max
    cutoff_date = days.days.ago

    deleted_count = @worker.worker_activities.where("occurred_at < ?", cutoff_date).delete_all

    render_success({
      message: "Cleaned up #{deleted_count} activities older than #{days} days",
      deleted_count: deleted_count,
      cutoff_date: cutoff_date.iso8601
    })
  end

  private

  def set_worker
    # Admin users can access all workers, regular users only their account's workers
    @worker = if current_user.has_permission?("system.workers.view") || current_user.has_permission?("super_admin")
                Worker.find(params[:worker_id])
    else
                current_account.workers.find(params[:worker_id])
    end
  rescue ActiveRecord::RecordNotFound
    render_error("Worker not found", status: :not_found)
  end

  def set_activity
    @activity = @worker.worker_activities.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Activity not found", status: :not_found)
  end

  def apply_status_filter(activities, status)
    case status
    when "success"
      activities.where("details->>'status' = 'success'")
    when "failed"
      activities.where("details->>'status' IN ('error', 'failure')")
    else
      activities
    end
  end

  def apply_date_range_filter(activities)
    activities = activities.where("occurred_at >= ?", Time.parse(params[:from])) if params[:from]
    activities = activities.where("occurred_at <= ?", Time.parse(params[:to])) if params[:to]
    activities
  rescue ArgumentError
    activities
  end

  def generate_activity_summary(worker, activities)
    recent_activities = activities.where("occurred_at > ?", 24.hours.ago)

    # Get endpoint usage statistics
    top_endpoints = get_top_endpoints(recent_activities)

    # Calculate success rate
    total_recent = recent_activities.count
    successful_recent = recent_activities.successful.count
    success_rate = total_recent > 0 ? (successful_recent.to_f / total_recent * 100).round(2) : 0

    # Calculate average response time
    activities_with_duration = recent_activities.where("details::jsonb ? 'duration'")
    avg_response_time = if activities_with_duration.any?
      durations = activities_with_duration.pluck(:details).map { |d| d["duration"].to_f }.compact
      durations.any? ? durations.sum / durations.size : 0
    else
      0
    end

    {
      total_recent: total_recent,
      successful_recent: successful_recent,
      failed_recent: recent_activities.failed.count,
      success_rate: success_rate,
      avg_response_time: avg_response_time.round(2),
      actions: recent_activities.group(:activity_type).count,
      top_endpoints: top_endpoints,
      last_activity_at: activities.order(:occurred_at).last&.occurred_at&.iso8601
    }
  end

  def get_top_endpoints(activities, limit = 10)
    endpoint_counts = {}

    # Aggregate endpoint usage from activities
    activities.each do |activity|
      details = activity.details || {}

      # Check for endpoint in different possible fields
      endpoint = details["endpoint"] || details["request_path"]
      next unless endpoint

      # Clean up endpoint (remove query parameters)
      clean_endpoint = endpoint.split("?").first
      endpoint_counts[clean_endpoint] = (endpoint_counts[clean_endpoint] || 0) + 1
    end

    # Sort by count and return top endpoints
    endpoint_counts
      .sort_by { |endpoint, count| -count }
      .first(limit)
      .map { |endpoint, count| { endpoint: endpoint, count: count } }
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
end
