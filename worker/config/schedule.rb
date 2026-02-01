# frozen_string_literal: true
# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Health Monitoring Jobs
every 5.minutes do
  runner "AiWorkflowHealthMonitoringJob.perform_async"
  runner "AiWorkflowEventIntegrationService.instance.monitor_system_health"
  runner "RefreshEmailSettingsJob.perform_async"
end

# System Cleanup Jobs
every 1.hour do
  runner "AiWorkflowCleanupJob.perform_async"
end

# DevOps Approval Token Expiry
every 1.hour do
  runner "Devops::ApprovalExpiryJob.perform_async"
end

# AI Workflow Approval Token Expiry
every 1.hour do
  runner "AiWorkflow::ApprovalExpiryJob.perform_async"
end

# Stuck Workflow Cleanup (more frequent)
every 5.minutes do
  runner "WorkflowCleanupJob.perform_async"
end

# AI Execution Timeout Cleanup (secondary cleanup with longer thresholds)
every 10.minutes do
  runner "AiExecutionTimeoutCleanupJob.perform_async"
end

every 6.hours do
  runner "AiWorkflowAnalyticsService.instance.cleanup_expired_cache"
end

# Cost Monitoring Jobs
every 1.hour do
  runner "AiWorkflowCostMonitoringJob.perform_async"
end

# Provider Health Checks
every 10.minutes do
  runner "AiProviderHealthCheckJob.perform_async"
end

# Analytics Cache Warming
every 15.minutes do
  runner "AiWorkflowAnalyticsCacheWarmupJob.perform_async"
end

# Weekly Reports
every :sunday, at: '6:00 am' do
  runner "AiWorkflowWeeklyReportJob.perform_async"
end

# Monthly Cleanup
every '0 0 1 * *' do  # First day of every month at midnight
  runner "AiWorkflowMonthlyCleanupJob.perform_async"
end