# frozen_string_literal: true

# Background job to generate weekly AI workflow analytics reports
# Runs every Sunday at 6:00 AM to compile and distribute weekly summaries
class AiWorkflowWeeklyReportJob < BaseJob
  queue_as :reports

  def execute
    log_info("Starting AI Workflow Weekly Report generation")

    report_period = {
      start_date: 1.week.ago.beginning_of_day.iso8601,
      end_date: Time.current.end_of_day.iso8601,
      week_number: Date.current.cweek,
      year: Date.current.year
    }

    report = {
      generated_at: Time.current.iso8601,
      period: report_period,
      status: 'generating',
      sections: {}
    }

    begin
      # Generate report sections
      report[:sections][:execution_summary] = generate_execution_summary(report_period)
      report[:sections][:performance_metrics] = generate_performance_metrics(report_period)
      report[:sections][:cost_analysis] = generate_cost_analysis(report_period)
      report[:sections][:provider_usage] = generate_provider_usage(report_period)
      report[:sections][:error_analysis] = generate_error_analysis(report_period)
      report[:sections][:top_workflows] = generate_top_workflows(report_period)
      report[:sections][:trends] = generate_trends(report_period)
      report[:sections][:recommendations] = generate_recommendations(report)

      report[:status] = 'completed'

      # Store the report
      store_report(report)

      # Distribute to stakeholders
      distribute_report(report)

      log_info("AI Workflow Weekly Report completed for week #{report_period[:week_number]}")
    rescue StandardError => e
      log_error("AI Workflow Weekly Report generation failed", e)
      report[:status] = 'failed'
      report[:error] = e.message
    end

    report
  end

  private

  def generate_execution_summary(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/execution_stats', {
        start_date: period[:start_date],
        end_date: period[:end_date]
      })
    end

    {
      total_executions: response['total_executions'] || 0,
      successful_executions: response['successful_executions'] || 0,
      failed_executions: response['failed_executions'] || 0,
      cancelled_executions: response['cancelled_executions'] || 0,
      success_rate: calculate_rate(response['successful_executions'], response['total_executions']),
      unique_workflows: response['unique_workflows'] || 0,
      unique_users: response['unique_users'] || 0,
      executions_by_day: response['executions_by_day'] || []
    }
  rescue StandardError => e
    log_error("Failed to generate execution summary", e)
    { error: e.message }
  end

  def generate_performance_metrics(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/performance_stats', {
        start_date: period[:start_date],
        end_date: period[:end_date]
      })
    end

    {
      average_execution_time_ms: response['average_execution_time_ms'] || 0,
      median_execution_time_ms: response['median_execution_time_ms'] || 0,
      p95_execution_time_ms: response['p95_execution_time_ms'] || 0,
      p99_execution_time_ms: response['p99_execution_time_ms'] || 0,
      average_nodes_per_workflow: response['average_nodes_per_workflow'] || 0,
      average_tokens_per_execution: response['average_tokens_per_execution'] || 0,
      total_tokens_used: response['total_tokens_used'] || 0,
      slowest_workflows: response['slowest_workflows'] || []
    }
  rescue StandardError => e
    log_error("Failed to generate performance metrics", e)
    { error: e.message }
  end

  def generate_cost_analysis(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_summary', {
        start_date: period[:start_date],
        end_date: period[:end_date],
        group_by: 'day'
      })
    end

    total_cost = response['total_cost'] || 0.0

    # Get previous week for comparison
    prev_response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_summary', {
        start_date: 2.weeks.ago.beginning_of_day.iso8601,
        end_date: 1.week.ago.end_of_day.iso8601
      })
    end

    prev_cost = prev_response['total_cost'] || 0.0
    cost_change = prev_cost.positive? ? ((total_cost - prev_cost) / prev_cost * 100).round(1) : 0

    {
      total_cost: total_cost,
      token_cost: response['token_cost'] || 0.0,
      api_call_cost: response['api_call_cost'] || 0.0,
      average_cost_per_execution: response['average_cost_per_execution'] || 0.0,
      cost_by_day: response['cost_by_day'] || [],
      previous_week_cost: prev_cost,
      week_over_week_change: cost_change,
      projected_monthly_cost: (total_cost * 4.33).round(2)
    }
  rescue StandardError => e
    log_error("Failed to generate cost analysis", e)
    { error: e.message }
  end

  def generate_provider_usage(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/cost_by_provider', {
        start_date: period[:start_date],
        end_date: period[:end_date]
      })
    end

    providers = response['providers'] || []

    {
      providers: providers.map do |p|
        {
          name: p['name'],
          total_cost: p['total_cost'] || 0.0,
          api_calls: p['api_calls'] || 0,
          token_count: p['token_count'] || 0,
          average_response_time_ms: p['average_response_time_ms'] || 0,
          error_rate: p['error_rate'] || 0.0
        }
      end,
      most_used_provider: providers.max_by { |p| p['api_calls'] || 0 }&.dig('name'),
      most_expensive_provider: providers.max_by { |p| p['total_cost'] || 0 }&.dig('name')
    }
  rescue StandardError => e
    log_error("Failed to generate provider usage", e)
    { error: e.message }
  end

  def generate_error_analysis(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/error_stats', {
        start_date: period[:start_date],
        end_date: period[:end_date]
      })
    end

    {
      total_errors: response['total_errors'] || 0,
      error_rate: response['error_rate'] || 0.0,
      errors_by_type: response['errors_by_type'] || [],
      errors_by_node_type: response['errors_by_node_type'] || [],
      most_common_errors: response['most_common_errors'] || [],
      errors_by_day: response['errors_by_day'] || [],
      recovered_executions: response['recovered_executions'] || 0,
      recovery_rate: response['recovery_rate'] || 0.0
    }
  rescue StandardError => e
    log_error("Failed to generate error analysis", e)
    { error: e.message }
  end

  def generate_top_workflows(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/top_workflows', {
        start_date: period[:start_date],
        end_date: period[:end_date],
        limit: 10
      })
    end

    workflows = response['workflows'] || []

    {
      by_executions: workflows.sort_by { |w| -(w['execution_count'] || 0) }.first(5),
      by_cost: workflows.sort_by { |w| -(w['total_cost'] || 0) }.first(5),
      by_success_rate: workflows.sort_by { |w| -(w['success_rate'] || 0) }.first(5),
      most_improved: response['most_improved'] || [],
      needs_attention: workflows.select { |w| (w['success_rate'] || 100) < 80 }
    }
  rescue StandardError => e
    log_error("Failed to generate top workflows", e)
    { error: e.message }
  end

  def generate_trends(period)
    response = with_api_retry do
      api_client.get('admin/ai_workflows/trends', {
        start_date: period[:start_date],
        end_date: period[:end_date],
        compare_weeks: 4
      })
    end

    {
      execution_trend: response['execution_trend'] || 'stable',
      cost_trend: response['cost_trend'] || 'stable',
      performance_trend: response['performance_trend'] || 'stable',
      error_rate_trend: response['error_rate_trend'] || 'stable',
      week_over_week_data: response['week_over_week_data'] || []
    }
  rescue StandardError => e
    log_error("Failed to generate trends", e)
    { error: e.message }
  end

  def generate_recommendations(report)
    recommendations = []

    # Check for high error rates
    error_analysis = report[:sections][:error_analysis] || {}
    if (error_analysis[:error_rate] || 0) > 10
      recommendations << {
        type: 'error_reduction',
        priority: 'high',
        message: "Error rate is #{error_analysis[:error_rate]}%. Review most common errors and implement fixes.",
        related_data: error_analysis[:most_common_errors]
      }
    end

    # Check for cost anomalies
    cost_analysis = report[:sections][:cost_analysis] || {}
    if (cost_analysis[:week_over_week_change] || 0) > 50
      recommendations << {
        type: 'cost_optimization',
        priority: 'medium',
        message: "Costs increased #{cost_analysis[:week_over_week_change]}% week-over-week. Review high-cost workflows.",
        related_data: report[:sections][:top_workflows]&.dig(:by_cost)
      }
    end

    # Check for performance issues
    performance = report[:sections][:performance_metrics] || {}
    if (performance[:p95_execution_time_ms] || 0) > 60_000 # 1 minute
      recommendations << {
        type: 'performance_optimization',
        priority: 'medium',
        message: "P95 execution time is #{(performance[:p95_execution_time_ms] / 1000.0).round(1)}s. Consider optimizing slow workflows.",
        related_data: performance[:slowest_workflows]
      }
    end

    # Check for underutilized providers
    provider_usage = report[:sections][:provider_usage] || {}
    providers = provider_usage[:providers] || []
    if providers.size > 1
      total_calls = providers.sum { |p| p[:api_calls] || 0 }
      providers.each do |provider|
        usage_percentage = total_calls.positive? ? (provider[:api_calls].to_f / total_calls * 100).round(1) : 0
        if usage_percentage < 5 && provider[:api_calls].positive?
          recommendations << {
            type: 'provider_review',
            priority: 'low',
            message: "Provider '#{provider[:name]}' has only #{usage_percentage}% of traffic. Consider consolidating or removing.",
            related_data: provider
          }
        end
      end
    end

    recommendations
  end

  def store_report(report)
    with_api_retry do
      api_client.post('admin/ai_workflow_reports', {
        report_type: 'weekly',
        period_start: report[:period][:start_date],
        period_end: report[:period][:end_date],
        week_number: report[:period][:week_number],
        year: report[:period][:year],
        data: report[:sections],
        recommendations: report[:sections][:recommendations],
        status: report[:status]
      })
    end
  rescue StandardError => e
    log_error("Failed to store weekly report", e)
  end

  def distribute_report(report)
    # Notify admins about the new report
    begin
      with_api_retry do
        api_client.post('admin/notifications/broadcast', {
          notification_type: 'weekly_report_ready',
          title: "AI Workflow Weekly Report - Week #{report[:period][:week_number]}",
          message: "Your weekly AI workflow report is ready for review.",
          target_permissions: ['admin.access', 'analytics.read'],
          metadata: {
            week_number: report[:period][:week_number],
            year: report[:period][:year],
            report_url: "/admin/ai-workflows/reports/weekly/#{report[:period][:year]}/#{report[:period][:week_number]}"
          }
        })
      end
      log_info("Distributed weekly report notification")
    rescue StandardError => e
      log_error("Failed to distribute weekly report notification", e)
    end
  end

  def calculate_rate(numerator, denominator)
    return 0.0 if denominator.nil? || denominator.zero?

    ((numerator || 0).to_f / denominator * 100).round(2)
  end
end
