# frozen_string_literal: true

module System
  # Daily reaper for old DiskImagePublications. Two-stage lifecycle:
  #
  #   - RETIRE: keep newest N per platform (platform.disk_image_retention_count,
  #     default 3). Older publications transition to :retired and have
  #     their file_object soft-deleted (operator can still rollback
  #     during the grace window).
  #
  #   - PURGE: retired publications past the grace window
  #     (default 7 days) get hard-deleted. Status flips to :purged.
  #     Rollback to a purged publication is rejected by the operator
  #     controller.
  #
  # Without this, FileStorageService accumulates 1-4GB blobs forever
  # (operators publish dozens of disk-image versions over a project's
  # lifetime). The retention service does the actual work via the
  # server-side worker_api endpoint; this job is the cron driver.
  #
  # Pattern mirrors System::ExpireUnclaimedDevicesJob — worker doesn't
  # touch the model, server endpoint scopes by current_worker.account.
  #
  # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — Chunk 2).
  class ExpireOldDiskImageFileObjectsJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 3

    def execute
      logger.info "[ExpireOldDiskImageFileObjectsJob] starting retention sweep"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/disk_image_publications/sweep_retention",
        {} # account-wide sweep — server scopes by current_worker.account
      )

      if response.is_a?(Hash) && response[:success] == false
        raise "retention sweep failed: #{response[:error]}"
      end

      summary = response.is_a?(Hash) ? response.dig(:data, :per_platform) : nil
      total_retired = summary.is_a?(Hash) ? summary.values.sum { |v| v[:retired].to_i } : 0
      total_purged  = summary.is_a?(Hash) ? summary.values.sum { |v| v[:purged].to_i }  : 0
      logger.info "[ExpireOldDiskImageFileObjectsJob] swept retired=#{total_retired} purged=#{total_purged}"
    end
  end
end
