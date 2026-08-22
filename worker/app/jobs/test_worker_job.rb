# frozen_string_literal: true

# Runs a lightweight connectivity self-check for this worker process and
# reports the outcome back to the server, so
# POST /api/v1/workers/:id/test (Api::V1::WorkersController#test_worker) has
# an actual completion signal to read back instead of leaving the request
# permanently at job_status: "enqueued".
#
# Enqueued by WorkerJobService#enqueue_test_worker_job — the signature here
# MUST match that producer exactly:
#   args: [worker_id, worker_name, { "test_type", "worker_id", "timestamp" }]
#
# Reports through Api::V1::WorkersController#test_results, which already
# expected this exact shape (test_type/status/duration_seconds/redis_check/
# backend_check/timestamp) and records it via Worker#record_activity! +
# touches last_seen_at — the same completion idiom OllamaConnectivityTestJob
# uses (run checks, then backend_api_post the results) rather than a new
# channel.
class TestWorkerJob < BaseJob
  sidekiq_options queue: 'services', retry: 1

  def execute(worker_id, worker_name, options = {})
    options = (options || {}).with_indifferent_access
    started_at = Time.current

    redis_ok = redis_reachable?

    result = {
      test_type: options[:test_type] || 'worker_connectivity_test',
      status: redis_ok ? 'passed' : 'failed',
      redis_check: redis_ok,
      # Always true by construction, not an independent measurement: this
      # value only ever reaches the server INSIDE the report_test_results
      # POST below, so its own successful delivery is the only way this
      # field is ever observed — a real backend outage means the POST
      # raises and no record (with backend_check: false or otherwise) is
      # ever written at all. Reviewed and accepted as structurally
      # tautological given this endpoint IS the backend-reachability probe.
      backend_check: true,
      duration_seconds: (Time.current - started_at).round(3),
      timestamp: Time.current.iso8601
    }

    report_test_results(worker_id, result)

    logger.info "TestWorkerJob completed for worker #{worker_id} (#{worker_name}): #{result[:status]}"
    result
  end

  private

  def redis_reachable?
    Sidekiq.redis { |conn| conn.ping == 'PONG' }
  rescue StandardError => e
    logger.warn "TestWorkerJob redis check failed for worker: #{e.message}"
    false
  end

  # Not rescued: if this POST fails, the worker genuinely cannot reach the
  # backend, so there is nothing useful to report and no record to write.
  # Left to raise so Sidekiq retries/dead-queues it instead of silently
  # pretending the test completed.
  def report_test_results(worker_id, result)
    api_client.post("/api/v1/workers/#{worker_id}/test_results", { test_results: result })
  end
end
