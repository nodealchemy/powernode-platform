# frozen_string_literal: true

module Git
  class RunnerHealthCheckJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    STALE_THRESHOLD_MINUTES = 5

    def execute
      log_info "Starting Git runner health checks"

      runners = fetch_online_runners
      log_info "Found online runners for health check", count: runners.size

      marked_offline = 0

      runners.each do |runner|
        next unless runner_is_stale?(runner)

        mark_runner_offline(runner)
        marked_offline += 1
      rescue StandardError => e
        log_error "Failed to check runner", e, runner_id: runner["id"]
      end

      log_info "Runner health check completed", checked: runners.size, marked_offline: marked_offline
    end

    private

    def fetch_online_runners
      response = api_client.get("/api/v1/internal/git/runners", { status: "online" })
      response.dig("data", "runners") || []
    end

    def runner_is_stale?(runner)
      return true if runner["last_seen_at"].nil?

      Time.parse(runner["last_seen_at"]) < STALE_THRESHOLD_MINUTES.minutes.ago
    end

    def mark_runner_offline(runner)
      api_client.put("/api/v1/internal/git/runners/#{runner['id']}/status", {
        status: "offline",
        busy: false,
        last_seen_at: Time.current.iso8601
      })
      log_info "Marked runner offline (stale)", runner_id: runner["id"], name: runner["name"]
    end
  end
end
