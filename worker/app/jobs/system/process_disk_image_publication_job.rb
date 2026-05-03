# frozen_string_literal: true

module System
  # Async tail of the disk-image publication webhook. The webhook
  # receiver acks CI fast (HMAC verify + DiskImagePublication upsert
  # ~50ms), then enqueues this job to do the long-pole work: oras pull
  # (1-4 GB), cosign verify-blob, cosign verify-attestation,
  # FileStorageService.upload_file, NodePlatform pointer flip,
  # FleetEvent emission, retention sweep enqueue.
  #
  # The actual work happens in the SERVER process via an internal
  # endpoint — this job is purely the async dispatch + retry mechanism.
  # Pattern mirrors System::ProcessModulePublicationJob.
  #
  # Retries: 5 attempts with exponential backoff. Transient registry
  # failures (oras pull 5xx, cosign timeout) recover. Validation
  # failures (sha mismatch, cosign verify fail) come back as 422 and
  # don't retry — the publication row's status flips to :failed and
  # the operator sees the error in FleetDashboard.
  #
  # Plan: docs/plans/wondrous-yawning-anchor.md (Phase 2 — Chunk 2).
  class ProcessDiskImagePublicationJob < BaseJob
    sidekiq_options queue: 'services', retry: 5

    # @param publication_id [String] UUID of the DiskImagePublication row
    def execute(publication_id)
      logger.info "[ProcessDiskImagePublicationJob] processing publication=#{publication_id}"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/disk_image_publications/process",
        publication_id: publication_id
      )

      if response.is_a?(Hash) && response[:success] == false
        # Worker_api endpoints emit `{success: false, error: "..."}` on
        # 4xx/5xx; surface as job failure so Sidekiq's retry kicks in
        # (idempotency makes re-runs safe — same git_sha returns
        # idempotent_hit on second attempt).
        raise "publication #{publication_id} processing failed: #{response[:error]}"
      end

      logger.info "[ProcessDiskImagePublicationJob] publication=#{publication_id} completed " \
                  "status=#{response.is_a?(Hash) ? response.dig(:data, :publication_status) : 'unknown'}"
    end
  end
end
