require_relative '../base_job'

# Job for generating PDF reports via the backend API
# Handles report generation requests from the frontend
class Reports::GenerateReportJob < BaseJob
  sidekiq_options queue: 'reports', 
                  retry: 2

  def execute(report_params)
    validate_required_params(report_params, 'report_type', 'account_id')
    
    logger.info "Generating #{report_params['report_type']} report for account #{report_params['account_id']}"
    
    # Verify account exists and get subscription info
    account_data = with_api_retry do
      api_client.get_account(report_params['account_id'])
    end
    
    logger.debug "Found account: #{account_data['name']}"
    
    # Generate the report via backend API
    report_request = build_report_request(report_params, account_data)
    
    report_result = with_api_retry do
      api_client.create_report(report_request)
    end
    
    logger.info "Successfully generated report #{report_result['id']} for account #{account_data['name']}"
    
    # Send notification if callback is configured
    if report_params['notification_callback']
      send_completion_notification(report_params['notification_callback'], report_result)
    end
    
    report_result
  end
  
  private
  
  def build_report_request(params, account_data)
    {
      report_type: params['report_type'],
      account_id: params['account_id'],
      format: params['format'] || 'pdf',
      date_range: build_date_range(params),
      options: build_report_options(params),
      generated_by: 'worker_service',
      metadata: {
        account_name: account_data['name'],
        generated_at: Time.current.iso8601,
        worker_job_id: jid
      }
    }
  end
  
  def build_date_range(params)
    return params['date_range'] if params['date_range']
    
    # Default to last 30 days if no range specified
    {
      start_date: 30.days.ago.to_date.iso8601,
      end_date: Date.current.iso8601
    }
  end
  
  def build_report_options(params)
    options = params['options'] || {}
    
    # Set default options based on report type
    case params['report_type']
    when 'revenue_report'
      options.reverse_merge!(
        'include_breakdown' => true,
        'show_trends' => true,
        'compare_previous_period' => true
      )
    when 'growth_report'
      options.reverse_merge!(
        'include_cohort_analysis' => true,
        'show_growth_rate' => true
      )
    when 'churn_report'
      options.reverse_merge!(
        'include_churn_reasons' => false,
        'segment_by_plan' => true
      )
    when 'customer_report'
      options.reverse_merge!(
        'include_demographics' => false,
        'show_customer_value' => true
      )
    when 'subscription_report'
      options.reverse_merge!(
        'group_by_plan' => true,
        'include_trial_data' => true
      )
    when 'executive_summary'
      options.reverse_merge!(
        'include_kpis' => true,
        'show_forecasting' => false
      )
    end
    
    options
  end
  
  def send_completion_notification(callback_url, report_result)
    return unless callback_url.is_a?(String) && callback_url.start_with?('http')
    
    notification_payload = {
      event: 'report_generated',
      report_id: report_result['id'],
      report_type: report_result['report_type'],
      account_id: report_result['account_id'],
      status: 'completed',
      generated_at: Time.current.iso8601,
      download_url: report_result['download_url']
    }
    
    begin
      # Use Faraday to send webhook notification
      connection = Faraday.new do |conn|
        conn.request :json
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 10
      end
      
      response = connection.post(callback_url, notification_payload)
      
      if response.success?
        logger.info "Sent completion notification to #{callback_url}"
      else
        logger.warn "Failed to send notification to #{callback_url}: #{response.status}"
      end
    rescue StandardError => e
      logger.error "Error sending notification to #{callback_url}: #{e.message}"
      # Don't fail the job for notification errors
    end
  end
end