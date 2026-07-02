# frozen_string_literal: true

# Worker Activities Controller
# Manages activity tracking and viewing for workers
class Api::V1::ActivitiesController < ApplicationController
  # Upper bound for the summary window: keeps the response payload (one bucket
  # per hour) and the query window bounded against arbitrary ?hours= input.
  MAX_SUMMARY_HOURS = 168 # 7 days

  before_action -> { require_permission("admin.workers.read") }
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
        activities: @activities.map { |activity| ActivitySerializer.serialize(activity) },
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
      activity: ActivitySerializer.serialize(@activity),
      worker: {
        id: @worker.id,
        name: @worker.name
      }
    })
  end

  # GET /api/v1/workers/:worker_id/activities/summary
  def summary
    hours = (params[:hours]&.to_i || 24).clamp(1, MAX_SUMMARY_HOURS)

    # Get activities within time range
    activities = @worker.worker_activities.where("occurred_at > ?", hours.hours.ago)

    # Hourly breakdown via a single set-based GROUP BY (was: one COUNT query per hour)
    hourly_counts = activities
                      .group(Arel.sql("date_trunc('hour', occurred_at)"))
                      .count
                      .transform_keys { |t| hour_bucket_key(t) }

    requests_by_hour = (0...hours).each_with_object({}) do |hour_ago, acc|
      hour_key = hour_ago.hours.ago.beginning_of_hour.strftime("%Y-%m-%d %H:00")
      acc[hour_key] = hourly_counts[hour_key] || 0
    end
    hourly_breakdown = requests_by_hour.dup

    total_requests = activities.count
    successful_requests = activities.successful.count

    summary_data = {
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: activities.failed.count,
      unique_actions: activities.distinct.pluck(:activity_type),
      last_activity: activities.order(:occurred_at).last&.occurred_at&.iso8601,
      requests_by_hour: requests_by_hour,
      actions_breakdown: activities.group(:activity_type).count,
      hourly_breakdown: hourly_breakdown,
      success_rate: total_requests > 0 ? (successful_requests.to_f / total_requests * 100).round(2) : 0
    }

    # Add average response time if available (AVG in the DB — was: pluck all details JSONB into Ruby)
    average_duration = activities.where("details->>'duration' IS NOT NULL")
                                 .average(Arel.sql("(details->>'duration')::float"))
    summary_data[:average_response_time] = average_duration.to_f.round(3) if average_duration

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
    @worker = if current_user.has_permission?("admin.workers.read") || current_user.has_permission?("system.admin")
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

  # Normalize a date_trunc('hour', ...) GROUP BY key (Time or String depending on
  # adapter casting) to the "%Y-%m-%d %H:00" bucket labels used in the response.
  def hour_bucket_key(time)
    time = Time.zone.parse(time) if time.is_a?(String)
    time.in_time_zone.strftime("%Y-%m-%d %H:00")
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

    # Calculate average response time (AVG in the DB — was: pluck full details JSONB
    # for every 24h row to average one float in Ruby)
    avg_response_time = recent_activities.where("details->>'duration' IS NOT NULL")
                                         .average(Arel.sql("(details->>'duration')::float"))
                                         .to_f

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

  # activity serialization extracted to ActivitySerializer
end
