# frozen_string_literal: true

module Devops
  class TemplateMaintenanceJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 1, dead: false

    STALE_TEMPLATE_DAYS = 90
    BUILD_RETENTION_DAYS = 30
    BUILDS_TO_KEEP = 5

    def execute
      log_info "[TemplateMaintenance] Starting weekly template maintenance"

      result = api_client.post(
        "/api/v1/internal/devops/maintenance/archive_stale_templates",
        {
          stale_days: STALE_TEMPLATE_DAYS,
          build_retention_days: BUILD_RETENTION_DAYS,
          builds_to_keep: BUILDS_TO_KEEP
        }
      )

      archived_count = result.dig("data", "archived_count") || 0
      builds_cleaned = result.dig("data", "builds_cleaned") || 0

      log_info "[TemplateMaintenance] Archived #{archived_count} stale templates, cleaned #{builds_cleaned} old builds"

      increment_counter("template_maintenance_run")
      track_cleanup_metrics(
        archived_templates: archived_count,
        cleaned_builds: builds_cleaned
      )
    end
  end
end
