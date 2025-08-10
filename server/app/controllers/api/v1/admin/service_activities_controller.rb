# Admin Service Activities Controller
# Manages service activity logs and monitoring
class Api::V1::Admin::ServiceActivitiesController < ApplicationController
  before_action :require_admin!
  before_action :set_service
  
  # GET /api/v1/admin/services/:service_id/activities
  def index
    @activities = @service.service_activities
                          .includes(:service)
                          .order(performed_at: :desc)
    
    # Apply filters
    @activities = @activities.by_action(params[:action]) if params[:action].present?
    @activities = @activities.where('performed_at >= ?', params[:from]) if params[:from].present?
    @activities = @activities.where('performed_at <= ?', params[:to]) if params[:to].present?
    
    if params[:status].present?
      case params[:status]
      when 'success'
        @activities = @activities.successful
      when 'failed'
        @activities = @activities.failed
      end
    end
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 25, 100].min
    offset = (page - 1) * per_page
    
    total = @activities.count
    @activities = @activities.limit(per_page).offset(offset)
    
    render json: {
      activities: @activities.map { |activity| activity_json(activity) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil
      },
      summary: activity_summary,
      service: {
        id: @service.id,
        name: @service.name,
        permissions: @service.permissions
      }
    }
  end
  
  # GET /api/v1/admin/services/:service_id/activities/:id
  def show
    @activity = @service.service_activities.find(params[:id])
    
    render json: {
      activity: activity_details(@activity),
      service: {
        id: @service.id,
        name: @service.name
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Activity not found' }, status: :not_found
  end
  
  # GET /api/v1/admin/services/:service_id/activities/summary
  def summary
    hours = params[:hours]&.to_i || 24
    summary_data = ServiceActivity.activity_summary(@service, hours)
    
    # Add additional breakdowns
    activities = @service.service_activities.where('performed_at > ?', hours.hours.ago)
    
    render json: {
      service: {
        id: @service.id,
        name: @service.name,
        permissions: @service.permissions
      },
      time_range: {
        hours: hours,
        from: hours.hours.ago.iso8601,
        to: Time.current.iso8601
      },
      summary: summary_data.merge({
        actions_breakdown: activities.group(:action).count,
        hourly_breakdown: activities.group_by_hour(:performed_at, last: hours).count,
        success_rate: calculate_success_rate(activities),
        average_response_time: calculate_average_response_time(activities)
      })
    }
  end
  
  # DELETE /api/v1/admin/services/:service_id/activities/cleanup
  def cleanup
    days_to_keep = params[:days]&.to_i || 30
    cutoff_date = days_to_keep.days.ago
    
    deleted_count = @service.service_activities
                            .where('performed_at < ?', cutoff_date)
                            .delete_all
    
    # Log the cleanup activity
    @service.record_activity!('activity_cleanup', {
      cleanup_by_user_id: current_user.id,
      days_kept: days_to_keep,
      records_deleted: deleted_count,
      cutoff_date: cutoff_date.iso8601,
      status: 'success'
    })
    
    render json: {
      message: "Cleaned up #{deleted_count} activity records older than #{days_to_keep} days",
      deleted_count: deleted_count,
      cutoff_date: cutoff_date.iso8601
    }
  end
  
  private
  
  def set_service
    if current_user.has_permission?('super_admin')
      # Super admins can access any service
      @service = Service.find(params[:service_id])
    else
      # Regular admins can only access services for their account
      @service = current_account.services.find(params[:service_id])
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Service not found' }, status: :not_found
  end
  
  def ensure_admin_access
    unless current_user.has_permission?('admin') || current_user.has_permission?('super_admin')
      render json: { error: 'Admin access required' }, status: :forbidden
    end
  end
  
  def activity_json(activity)
    {
      id: activity.id,
      action: activity.action,
      performed_at: activity.performed_at.iso8601,
      ip_address: activity.ip_address,
      user_agent: activity.user_agent&.truncate(100),
      successful: activity.successful?,
      failed: activity.failed?,
      duration: activity.duration,
      response_status: activity.response_status,
      request_path: activity.request_path,
      error_message: activity.error_message&.truncate(200)
    }
  end
  
  def activity_details(activity)
    activity_json(activity).merge({
      details: activity.details,
      user_agent: activity.user_agent, # Full user agent
      error_message: activity.error_message # Full error message
    })
  end
  
  def activity_summary
    recent_activities = @service.service_activities.recent
    
    {
      total_recent: recent_activities.count,
      successful_recent: recent_activities.successful.count,
      failed_recent: recent_activities.failed.count,
      actions: recent_activities.group(:action).count,
      last_activity_at: @service.last_activity&.performed_at&.iso8601
    }
  end
  
  def calculate_success_rate(activities)
    return 0 if activities.empty?
    
    successful = activities.successful.count
    total = activities.count
    
    (successful.to_f / total * 100).round(2)
  end
  
  def calculate_average_response_time(activities)
    durations = activities.where.not("details->>'duration' IS NULL")
                          .pluck("(details->>'duration')::float")
    
    return nil if durations.empty?
    
    (durations.sum / durations.size).round(3)
  end
end