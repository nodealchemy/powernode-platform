# frozen_string_literal: true

module System
  # Async tail of the Gitea module-publish webhook. The webhook receiver
  # acks Gitea fast (sync portion: HMAC + module lookup + bare version
  # snapshot ~50ms), then enqueues this job to do the long-pole work:
  # manifest fetch from Gitea, OCI registry pull + cosign verify,
  # ManifestImportService re-import, skill registration, FleetEvent
  # emission.
  #
  # The actual work happens in the SERVER process via an internal
  # endpoint — this job is purely the async dispatch + retry mechanism.
  # Keeping logic on the server side means we don't duplicate the
  # System::* service stack in the worker, and the existing rspec
  # coverage for those services stays meaningful.
  #
  # Retries: BaseJob's exponential backoff already covers the common
  # registry-flake case (manifest fetch 5xx, cosign verify timeout).
  # Validation failures (missing tag, version mismatch) come back from
  # the endpoint as 422 and don't retry.
  #
  # Reference: webhook async audit follow-up 2026-05-02.
  class ProcessModulePublicationJob < BaseJob
    sidekiq_options queue: 'services', retry: 5

    # @param node_module_id [String] UUID of the NodeModule
    # @param tag [String] Git tag the publication is for (e.g. "v1.2.3")
    def execute(node_module_id, tag)
      logger.info "[ProcessModulePublicationJob] processing module=#{node_module_id} tag=#{tag}"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/module_publications/process",
        node_module_id: node_module_id,
        tag: tag
      )

      if response.is_a?(Hash) && response[:success] == false
        # Worker_api endpoints emit `{success: false, error: "..."}` on
        # 4xx/5xx; surface as a job failure so Sidekiq's retry kicks in.
        # Validation-class errors (4xx) won't actually recover on retry,
        # but they're rare and the audit trail in the dead queue is more
        # useful than silent loss.
        raise BackendApiClient::ApiError, "process_publication failed: #{response[:error] || 'unknown'}"
      end

      logger.info "[ProcessModulePublicationJob] success module=#{node_module_id} tag=#{tag}"
      response
    end
  end
end
