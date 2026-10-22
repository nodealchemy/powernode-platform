# frozen_string_literal: true

require "rails_helper"

# Improvement 01a163c7-0d7a — worker -> server route census.
#
# Every `/api/v1/...` path the standalone worker (core and every extension's
# worker/app) sends to this server must be a route the server draws. A path
# nothing routes is a silent 404: the job logs a warning or swallows the
# error, and whatever it was reporting never lands. Extraction and matching
# live in spec/support/worker_route_census.rb (the inverse of
# RouteCallerCoverageChecker, which proves every route has a caller).
#
# Three lists, each entry carrying a reason:
#   EXTERNAL_API_FILES — files whose `/api/v1/...` strings address a THIRD
#     party's API (Gitea's REST API is rooted at /api/v1 too), never this
#     server. Their strings are not censused.
#   KNOWN_DEAD — calls that 404 today and are tracked for a fix. Closed to
#     new entries; an entry whose call routes again (or is gone) fails as
#     stale, so the list can only shrink.
#   Unresolved call sites (a path argument the scanner cannot see) are
#     printed, never failed on.
RSpec.describe "worker -> server internal route census" do
  EXTERNAL_API_FILES = {
    "worker/app/services/devops/git_providers/gitea_provider.rb" =>
      "Gitea's own REST API (/api/v1/repos/..., /api/v1/user), sent to the git provider's host through the provider's connection, not to this server"
  }.freeze

  # key => reason. Key is "VERB /api/v1/path" with `:x` for each dynamic
  # segment ("ANY" when the scanner cannot see the verb). The baseline is
  # every call that 404'd when the census landed (improvement 01a163c7-0d7a);
  # each is fixed by restoring its route or deleting its caller, and its
  # entry deleted in the same change.
  KNOWN_DEAD = {
    # accounts
    "GET /api/v1/accounts" => "baseline 01a163c7: path routes, verb does not",
    # admin
    "GET /api/v1/admin/accounts" => "baseline 01a163c7: no route",
    "POST /api/v1/admin/maintenance/backups" => "baseline 01a163c7: path routes, verb does not",
    # ai
    "POST /api/v1/ai/agents/:x/memory/inject" => "baseline 01a163c7: path routes, verb does not",
    "GET /api/v1/ai/intelligence/monitoring/predictive_failure" => "baseline 01a163c7: no route",
    "GET /api/v1/ai/intelligence/monitoring/sla_breach_risk" => "baseline 01a163c7: no route",
    "POST /api/v1/ai/monitoring/broadcast_metrics" => "baseline 01a163c7: no route",
    "GET /api/v1/ai/agent_executions/:x" => "baseline 01a163c7: no route",
    # analytics
    "GET /api/v1/analytics/live" => "baseline 01a163c7: no route",
    "POST /api/v1/analytics/live" => "baseline 01a163c7: no route",
    "POST /api/v1/analytics/update_revenue_snapshots" => "baseline 01a163c7: no route",
    "POST /api/v1/analytics/recalculate" => "baseline 01a163c7: no route",
    "GET /api/v1/analytics/:x" => "baseline 01a163c7: no route",
    "GET /api/v1/analytics/export" => "baseline 01a163c7: no route",
    # devices
    "DELETE /api/v1/devices/by_token/:x" => "baseline 01a163c7: no route",
    # email_deliveries
    "POST /api/v1/email_deliveries" => "baseline 01a163c7: no route",
    "PATCH /api/v1/email_deliveries/:x" => "baseline 01a163c7: no route",
    # git
    "GET /api/v1/git/repositories/:x/pipelines/:x/jobs/:x" => "baseline 01a163c7: no route",
    "GET /api/v1/git/repositories/:x/pipelines/:x/jobs/:x/logs" => "baseline 01a163c7: no route",
    # internal/ai
    "POST /api/v1/internal/ai/conversations/:x/broadcast" => "baseline 01a163c7: no route",
    # internal/data_retention_policies
    "PATCH /api/v1/internal/data_retention_policies/:x" => "baseline 01a163c7: no route",
    # internal/devops
    "PATCH /api/v1/internal/devops/claude_invocations/:x" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/devops/deployments/:x" => "baseline 01a163c7: no route",
    "PATCH /api/v1/internal/devops/deployments/:x" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/devops/pipeline_runs/:x/step_executions" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/devops/webhook_events/:x" => "baseline 01a163c7: no route",
    "PATCH /api/v1/internal/devops/webhook_events/:x" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/devops/pipelines" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/devops/pipeline_runs" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/devops/pipeline_runs/:x/execute" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/devops/swarm/deployments/:x" => "baseline 01a163c7: path routes, verb does not",
    "POST /api/v1/internal/devops/pull_requests" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/devops/runners/dispatch" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/devops/comments" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/devops/artifacts" => "baseline 01a163c7: no route",
    # internal/file_processing_jobs
    "GET /api/v1/internal/file_processing_jobs/:x" => "baseline 01a163c7: no route",
    "PUT /api/v1/internal/file_processing_jobs/:x" => "baseline 01a163c7: no route",
    # internal/files
    "GET /api/v1/internal/files/:x/content" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/files/:x/quarantine" => "baseline 01a163c7: no route",
    # internal/git
    "PATCH /api/v1/internal/git/credentials/:x" => "baseline 01a163c7: path routes, verb does not",
    "POST /api/v1/internal/git/approvals/expire_stale" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/git/approvals/:x" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/git/pipelines/sync_jobs" => "baseline 01a163c7: path routes, verb does not",
    "GET /api/v1/internal/git/schedules/due" => "baseline 01a163c7: no route",
    "GET /api/v1/internal/git/schedules/:x" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/git/schedules/:x/record_run" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/git/webhook_events/:x/trigger_workflows" => "baseline 01a163c7: no route",
    # internal/retention
    "PATCH /api/v1/internal/retention/activity/anonymize" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/activity" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/sessions" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/email_logs" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/webhook_logs" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/api_logs" => "baseline 01a163c7: no route",
    "PATCH /api/v1/internal/retention/analytics/anonymize" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/analytics" => "baseline 01a163c7: no route",
    "DELETE /api/v1/internal/retention/files" => "baseline 01a163c7: no route",
    "POST /api/v1/internal/retention/audit_logs/archive" => "baseline 01a163c7: no route",
    "PATCH /api/v1/internal/retention/audit_logs/anonymize" => "baseline 01a163c7: no route",
    # invoices
    "GET /api/v1/invoices" => "baseline 01a163c7: no route",
    "POST /api/v1/invoices" => "baseline 01a163c7: no route",
    # notifications
    "PATCH /api/v1/notifications/:x" => "baseline 01a163c7: path routes, verb does not",
    # reports
    "POST /api/v1/reports/generate" => "baseline 01a163c7: no route",
    "POST /api/v1/reports" => "baseline 01a163c7: path routes, verb does not",
    "PUT /api/v1/reports/scheduled/:x" => "baseline 01a163c7: no route",
    # subscriptions
    "GET /api/v1/subscriptions" => "baseline 01a163c7: no route",
    "PATCH /api/v1/subscriptions/:x" => "baseline 01a163c7: no route",
    # users
    "GET /api/v1/users/:x/notification_preferences" => "baseline 01a163c7: no route",
    "GET /api/v1/users/:x/devices" => "baseline 01a163c7: no route",
    # worker
    "POST /api/v1/worker/files/:x/quarantine" => "baseline 01a163c7: no route"
  }.freeze

  let(:calls) { WorkerRouteCensus.calls.reject { |c| EXTERNAL_API_FILES.key?(c.file) } }

  def failing_calls
    calls.filter_map do |call|
      status = WorkerRouteCensus.classify(call)
      [ call, status ] unless status == :ok
    end
  end

  it "requires every external-API file and known-dead entry to carry a reason" do
    blank = EXTERNAL_API_FILES.merge(KNOWN_DEAD).select { |_k, reason| reason.to_s.strip.empty? }
    expect(blank).to be_empty, "entries with no reason: #{blank.keys.join(', ')}"
  end

  it "names only external-API files that exist" do
    missing = EXTERNAL_API_FILES.keys.reject { |f| File.exist?(File.join(WorkerRouteCensus::REPO_ROOT, f)) }
    expect(missing).to be_empty, "EXTERNAL_API_FILES entries for files that no longer exist: #{missing.join(', ')}"
  end

  it "finds the worker's calls and the server's routes (sanity)" do
    expect(calls.size).to be > 100
    expect(WorkerRouteCensus.route_matchers.size).to be > 1000
    # The census must see extension worker calls and extension-drawn routes.
    expect(calls.map(&:file)).to include(a_string_starting_with("extensions/system/worker/app/"))
    expect(WorkerRouteCensus.classify(WorkerRouteCensus::Call.new(verb: "GET", path: "/api/v1/internal/users/:x"))).to eq(:ok)
  end

  it "routes every worker call to /api/v1 that is not a known-dead entry" do
    report = failing_calls.reject { |call, _status| KNOWN_DEAD.key?(call.key) }

    unresolved = WorkerRouteCensus.unresolved.reject { |u| EXTERNAL_API_FILES.key?(u.file) }
    unless unresolved.empty?
      RSpec.configuration.reporter.message(
        "worker route census: #{unresolved.size} unresolved call site(s) (not failed):\n" +
        unresolved.map { |u| "  #{u.file}:#{u.line} — #{u.reason}" }.join("\n")
      )
    end

    grouped = report.group_by { |call, _status| call.area }.sort.map do |area, rows|
      lines = rows.group_by { |call, status| [ call.key, status ] }.map do |(key, status), hits|
        "    #{key}#{status == :verb_mismatch ? '  [path routes, verb does not]' : ''}\n" +
          hits.map { |call, _| "      #{call.file}:#{call.line}" }.join("\n")
      end
      "  #{area} (#{lines.size})\n#{lines.join("\n")}"
    end

    expect(report).to be_empty, <<~MSG
      #{report.map { |c, _| c.key }.uniq.size} worker call(s) to /api/v1 match no server route (they 404):

      #{grouped.join("\n")}

      For each: restore the route (when the worker reports something real that
      nothing else receives) or delete the caller (dead or superseded code).
      KNOWN_DEAD is closed to new entries.
    MSG
  end

  it "keeps KNOWN_DEAD free of entries whose call now routes or is gone" do
    still_dead = failing_calls.map { |call, _| call.key }.to_set
    stale = KNOWN_DEAD.keys.reject { |key| still_dead.include?(key) }
    expect(stale).to be_empty, "KNOWN_DEAD entries that no longer 404 — delete them:\n#{stale.join("\n")}"
  end

  describe "the scanner" do
    def scan(source)
      WorkerRouteCensus.scan_source(source)
    end

    it "turns each whole-segment interpolation into a dynamic segment and takes the call's verb" do
      calls, = scan(%(api_client.post("/api/v1/internal/ai/agents/\#{agent["id"]}/runs", {})\n))
      expect(calls.map(&:key)).to eq([ "POST /api/v1/internal/ai/agents/:x/runs" ])
    end

    it "splices a path constant, a format placeholder, and drops a base URL and query string" do
      source = <<~'RUBY'
        BASE = "/api/v1/internal/devops".freeze
        CONCLUDE = "#{BASE}/runs/%{id}/conclude"
        def go = api_client.patch(format(CONCLUDE, id: 1))
        url = "#{ENV['BACKEND_API_URL']}/api/v1/reports/#{id}?page=#{n}"
      RUBY
      calls, = scan(source)
      expect(calls.map(&:key)).to include(
        "PATCH /api/v1/internal/devops/runs/:x/conclude",
        "ANY /api/v1/reports/:x"
      )
    end

    it "takes the verb of a later call that passes a local path variable" do
      calls, = scan(%(path = "/api/v1/internal/things/run_all"\nresponse = api_client.post(path, {})\n))
      expect(calls.map(&:key)).to eq([ "POST /api/v1/internal/things/run_all" ])
    end

    it "reports, rather than guesses, a path it cannot resolve" do
      calls, unresolved = scan(%(api_client.get("/api/v1/internal/x/\#{id}.json")\napi_client.get("/api/v1/internal/x\#{suffix}")\napi_client.get(some_path)\n))
      expect(calls).to be_empty
      expect(unresolved.size).to eq(3)
    end

    it "never reads a comment as a call" do
      calls, = scan(%(# api_client.get("/api/v1/internal/ghost")\n))
      expect(calls).to be_empty
    end

    it "classifies a missing route as dead and a wrong verb as a verb mismatch" do
      ghost = WorkerRouteCensus::Call.new(verb: "POST", path: "/api/v1/internal/census_ghost/:x")
      expect(WorkerRouteCensus.classify(ghost)).to eq(:dead)
      wrong_verb = WorkerRouteCensus::Call.new(verb: "DELETE", path: "/api/v1/internal/users/:x")
      expect(WorkerRouteCensus.classify(wrong_verb)).to eq(:verb_mismatch)
    end
  end
end
