# frozen_string_literal: true

require_relative '../base_job'

# Job for processing scheduled reports
# Runs on a cron schedule to generate automated reports
class Reports::ScheduledReportJob < BaseJob
  sidekiq_options queue: 'reports',
                  retry: 1

  def execute(scheduled_report_id)
    logger.info "Processing scheduled report #{scheduled_report_id}"
    
    # Get scheduled report details from backend
    scheduled_report = with_api_retry do
      api_client.get_scheduled_reports(id: scheduled_report_id)
    end
    
    if scheduled_report.empty?
      logger.warn "Scheduled report #{scheduled_report_id} not found"
      return
    end
    
    report_config = scheduled_report.first
    
    unless report_config['active']
      logger.info "Scheduled report #{scheduled_report_id} is inactive, skipping"
      return
    end
    
    # Check if report is due for execution
    next_run_at = Time.parse(report_config['next_run_at'])
    if next_run_at > Time.current
      logger.info "Scheduled report #{scheduled_report_id} not due until #{next_run_at}, skipping"
      return
    end
    
    logger.info "Executing scheduled #{report_config['report_type']} report for account #{report_config['account_id']}"
    
    # Build report parameters from scheduled config
    report_params = build_scheduled_report_params(report_config)
    
    # Generate the report
    Reports::GenerateReportJob.perform_async(report_params)
    
    # Update next run time
    update_next_run_time(scheduled_report_id, report_config)
    
    logger.info "Successfully scheduled report generation for #{scheduled_report_id}"
  end
  
  private
  
  def build_scheduled_report_params(config)
    {
      'report_type' => config['report_type'],
      'account_id' => config['account_id'],
      'format' => config['format'] || 'pdf',
      'date_range' => calculate_date_range(config),
      'options' => config['options'] || {},
      'notification_callback' => config['webhook_url'],
      'scheduled_report_id' => config['id']
    }
  end
  
  def calculate_date_range(config)
    # Calculate date range based on frequency
    end_date = Date.current
    
    start_date = case config['frequency']
                 when 'daily'
                   1.day.ago.to_date
                 when 'weekly'
                   1.week.ago.to_date
                 when 'monthly'
                   1.month.ago.to_date
                 else
                   30.days.ago.to_date
                 end
    
    {
      start_date: start_date.iso8601,
      end_date: end_date.iso8601
    }
  end
  
  def update_next_run_time(scheduled_report_id, config)
    next_run_at = calculate_next_run_time(config)
    
    update_data = {
      next_run_at: next_run_at.iso8601,
      last_run_at: Time.current.iso8601
    }
    
    with_api_retry do
      api_client.update_scheduled_report(scheduled_report_id, update_data)
    end
    
    logger.info "Updated next run time for scheduled report #{scheduled_report_id} to #{next_run_at}"
  rescue StandardError => e
    logger.error "Failed to update next run time for scheduled report #{scheduled_report_id}: #{e.message}"
    # Don't fail the job for this error
  end
  
  def calculate_next_run_time(config)
    frequency = config['frequency']
    scheduled_time = config['scheduled_time'] || '09:00'
    
    # Parse scheduled time (format: "HH:MM")
    hour, minute = scheduled_time.split(':').map(&:to_i)
    
    case frequency
    when 'daily'
      next_time = 1.day.from_now.beginning_of_day + hour.hours + minute.minutes
    when 'weekly'
      # Weekly reports run on the same day of week
      next_time = 1.week.from_now.beginning_of_day + hour.hours + minute.minutes
    when 'monthly'
      # Monthly reports run on the same day of month (or last day if original date doesn't exist)
      current_day = Date.current.day
      next_month = 1.month.from_now.to_date
      
      # Handle month-end dates (e.g., Jan 31 -> Feb 28/29)
      target_day = [current_day, next_month.end_of_month.day].min
      next_date = next_month.beginning_of_month + (target_day - 1).days
      
      next_time = next_date.to_time + hour.hours + minute.minutes
    else
      # Default to daily
      next_time = 1.day.from_now.beginning_of_day + hour.hours + minute.minutes
    end
    
    # Ensure next time is in the future
    next_time < Time.current ? next_time + 1.day : next_time
  end
end