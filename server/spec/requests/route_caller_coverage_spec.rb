# frozen_string_literal: true

require "rails_helper"

# fc-27 — Route caller coverage guard.
#
# Every non-internal api/v1 route (any controller NOT under
# Api::V1::Internal::*, which is service-token-authed worker traffic that by
# design has no frontend/MCP caller) must have EITHER:
#   - a frontend literal caller (core + public/private extension frontend), or
#   - an MCP-tool / extension-service caller, or
#   - a worker-job or Go node-agent caller, or
#   - be an INBOUND webhook/callback receiver, listed below with a reason
#     (a third party calls these, not our own frontend or MCP tooling — a
#     literal-string search can never find that caller because it doesn't
#     exist in this codebase).
#
# See spec/support/route_caller_coverage_checker.rb for the two-tier
# literal/token matching heuristic, and
# spec/fixtures/route_caller_coverage/baseline_allowlist.txt for the
# pre-existing surface the heuristic cannot currently prove covered (real
# dead code and heuristic gaps both land there — this guard's job is to catch
# a NEW zero-caller route, not to re-litigate the existing surface).
RSpec.describe "Route caller coverage", type: :routing do
  # One-way ratchet: pinned to the baseline's EXACT size. A shrink (a route
  # gets a caller, or is deleted) must lower this in the same diff, so the
  # freed slot can never be silently re-spent; growing it is never an option.
  MAX_BASELINE_SIZE = 452
  # controller#action => human reason it is legitimately caller-less from
  # OUR OWN code's point of view. Every entry here is a receiver: the request
  # originates from a third party (a git/registry provider, a spawned agent
  # container, an OAuth redirect, a deploying pipeline), authenticated by a
  # signature/token/state param rather than our own session — never by a
  # frontend fetch or an MCP tool call.
  WEBHOOK_ALLOWLIST = {
    "api/v1/webhooks/container_registry#handle" =>
      "Inbound container-registry push notification; signature-verified (skip_before_action :authenticate_request).",
    "api/v1/webhooks/git#handle" =>
      "Inbound git-provider (GitHub/GitLab/Gitea) webhook; signature-verified.",
    "api/v1/system/webhooks/gitea_module#handle" =>
      "Inbound Gitea module-publish webhook receiver (system extension).",
    "api/v1/system/webhooks/module_sbom#create" =>
      "Inbound SBOM-ingestion webhook receiver (system extension).",
    "api/v1/system/webhooks/platform_push#handle" =>
      "Inbound platform-push webhook receiver (system extension).",
    "api/v1/chat/webhooks#receive" =>
      "Inbound chat-provider (e.g. SMS) message webhook; signature-verified, auth skipped by design.",
    "api/v1/chat/webhooks#verify" =>
      "Inbound chat-provider webhook verification handshake; signature-verified, auth skipped by design.",
    "api/v1/ai/ralph_loop_webhooks#status" =>
      "Token-scoped status poll by whichever external system minted the loop's webhook token " \
      "(scope \"ralph_loops/webhook/:token\") — the caller is that external system, not our frontend/MCP.",
    "api/v1/ai/code_factory#webhook" =>
      "Inbound CI/build-system webhook receiver.",
    "api/v1/ai/agent_containers#callback" =>
      "Inbound callback FROM a spawned agent container reporting back to the platform (\"Container sends " \
      "messages back to platform\") — the caller is the container process, not our frontend/MCP.",
    "api/v1/ai/missions#deploy_callback" =>
      "Inbound callback FROM a deploying container/pipeline reporting its own deploy status back to the mission.",
    "api/v1/git/providers#oauth_callback" =>
      "Inbound OAuth authorization-code redirect FROM the git provider (params: code, state) — the browser " \
      "is redirected here by the provider, not fetched by our own frontend code."
  }.freeze

  # controller#action => { offer:, reason: } for a caller-less route kept
  # ONLY while an operator decides whether it goes. Not the baseline (which
  # is closed): each entry names the open offer that decides it, and is
  # removed when that offer is decided — by a caller, or by deleting the route.
  PENDING_DECISION = {
    "api/v1/admin_settings#clear_blacklisted_tokens" => {
      offer: "01a0d68f",
      reason: "fc-21 deleted its only frontend caller; whether the endpoint goes too is the operator's call."
    },
    "api/v1/admin_settings#regenerate_jwt_secret" => {
      offer: "01a0d68f",
      reason: "fc-21 deleted its only frontend caller; whether the endpoint goes too is the operator's call."
    }
  }.freeze

  let(:baseline_allowlist) do
    Rails.root.join("spec/fixtures/route_caller_coverage/baseline_allowlist.txt")
      .readlines
      .map(&:strip)
      .reject { |line| line.empty? || line.start_with?("#") }
      .to_set
  end

  it "requires every webhook-allowlist entry to carry a non-blank reason" do
    expect(WEBHOOK_ALLOWLIST).not_to be_empty
    blank = WEBHOOK_ALLOWLIST.select { |_key, reason| reason.to_s.strip.empty? }
    expect(blank).to be_empty, "webhook allowlist entries with no reason: #{blank.keys.join(', ')}"
  end

  it "flags every non-internal api/v1 route with no caller, webhook reason, or baseline entry" do
    routes = RouteCallerCoverageChecker.non_internal_api_v1_routes
    expect(routes).not_to be_empty # sanity: the checker actually found the route set

    new_hits = routes.reject do |route|
      WEBHOOK_ALLOWLIST.key?(route.key) ||
        PENDING_DECISION.key?(route.key) ||
        baseline_allowlist.include?(route.key) ||
        RouteCallerCoverageChecker.covered?(route)
    end

    expect(new_hits).to be_empty, <<~MSG
      #{new_hits.size} route(s) have no frontend/MCP-tool caller and are not on the
      webhook allowlist or the pre-existing baseline:

      #{new_hits.map(&:key).sort.join("\n")}

      For each: add a caller or delete the route. (A genuine INBOUND receiver — a
      third party calls it, never our frontend/MCP — takes a reasoned
      WEBHOOK_ALLOWLIST entry above instead.) The baseline is closed to new entries.
    MSG
  end

  # Demonstrates the checker is a real detector, not a vacuous pass. Building
  # a synthetic Route rather than mutating config/routes.rb: Rails.application
  # .routes.draw replaces the ENTIRE route set for the process, so injecting
  # one extra route safely (without leaking into the ~2,400 other examples
  # that share this process) isn't practical inside a shared-process request
  # spec. This unit-tests the same #covered? the coverage test above calls,
  # against a path guaranteed to appear nowhere in the corpus — so a real
  # route this shape, added to routes.rb and left off both allowlists, would
  # fail the test directly above.
  it "detects an uncovered route — proves the checker is not vacuously green" do
    fake_route = RouteCallerCoverageChecker::Route.new(
      "GET", "/api/v1/definitely_not_a_real_endpoint_zzz_fc27", "api/v1/fake_fc27", "ghost_action"
    )

    expect(RouteCallerCoverageChecker.covered?(fake_route)).to be(false)
    expect(WEBHOOK_ALLOWLIST).not_to have_key(fake_route.key)
    expect(baseline_allowlist).not_to include(fake_route.key)
  end

  # Review round 1 (MED): the Tier-1 regex was unanchored, so a fake route
  # sharing a word with a TS path alias (`@/shared/components/Foo`,
  # `@/shared/hooks/useFoo`, `@/features/ai/...`) read as "covered" purely
  # because the alias segment happened to match. Each of these paths is
  # deliberately built from words that appear constantly in real import
  # lines, so a regression here reads as a false "covered", not a crash.
  it "never counts a TS import-path alias segment as a route caller" do
    %w[
      /api/v1/components/:id
      /api/v1/hooks/:id
      /api/v1/features/:id
      /api/v1/utils
      /api/v1/types
    ].each do |path|
      fake_route = RouteCallerCoverageChecker::Route.new("GET", path, "api/v1/fake_fc27", "ghost_action")
      expect(RouteCallerCoverageChecker.covered?(fake_route)).to be(false), "#{path} should not read as covered"
    end
  end

  # Review round 2 (HIGH): false negatives. Real callers written in these
  # shapes used to read as uncovered and landed in the baseline.
  describe "caller shapes (Tier 1 literal matching)" do
    def literal_caller?(path, text, known_bases: {})
      RouteCallerCoverageChecker.literal_caller_in?(path, text, known_bases: known_bases)
    end

    it "counts a path followed directly by a trailing ${...} interpolation" do
      expect(literal_caller?("/api/v1/audit_logs/security_summary",
                             "const response = await api.get(`/audit_logs/security_summary${params}`);")).to be(true)
      expect(literal_caller?("/api/v1/ai/agents/:agent_id/intelligence/experience_replays",
                             "this.get(`/ai/agents/${agentId}/intelligence/experience_replays${queryString}`);"))
        .to be(true)
      expect(literal_caller?("/api/v1/ai/coordination/pressure_fields",
                             "this.get(`/ai/coordination/pressure_fields${queryString}`);")).to be(true)
    end

    it "resolves a base-path variable declared in the same file" do
      text = <<~TS
        class MonitoringApiService {
          private basePath = '/ai/monitoring';
          detailed() { return this.get(`${this.basePath}/health/detailed`); }
        }
      TS

      expect(literal_caller?("/api/v1/ai/monitoring/health/detailed", text)).to be(true)
    end

    it "resolves an inherited base-path variable from the corpus-wide map" do
      text = "return this.get(`${this.baseNamespace}/execution_traces/${traceId}`);"

      expect(literal_caller?("/api/v1/ai/execution_traces/:id", text, known_bases: { "baseNamespace" => "/ai" }))
        .to be(true)
    end

    # A bare leading `}` would credit the route the call does NOT go to:
    # `${this.basePath}/health/detailed` with basePath '/ai/monitoring' calls
    # ai/monitoring#health_detailed, not the top-level health#detailed.
    it "does not credit the un-prefixed route a base-path variable was spliced onto" do
      text = <<~TS
        private basePath = '/ai/monitoring';
        detailed() { return this.get(`${this.basePath}/health/detailed`); }
      TS

      expect(literal_caller?("/api/v1/health/detailed", text)).to be(false)
    end

    it "does not treat an unresolved leading variable as a base path" do
      expect(literal_caller?("/api/v1/pipelines", "this.get(`${somethingUnknown}/pipelines`);")).to be(false)
    end

    it "does not treat a mid-string interpolation's closing brace as a path boundary" do
      text = "api.get(`/supply_chain/sboms/${sbomId}/components/${componentId}/vulnerabilities`);"

      expect(literal_caller?("/api/v1/components/:id", text)).to be(false)
    end

    # Review round 4: the worker (standalone Sidekiq) and the Go node agent
    # call the API over HTTP too; a route only they call is not dead.
    it "counts a worker job's server_post path literal" do
      text = <<~RUBY
        response = server_post(
          "/api/v1/admin/daily_summaries/generate",
          { account_id: account_id }
        )
      RUBY

      expect(literal_caller?("/api/v1/admin/daily_summaries/generate", text)).to be(true)
    end

    it "counts a Go agent's fmt.Sprintf path with a %s segment" do
      text = 'path := fmt.Sprintf("/api/v1/system/node_api/storage_assignments/%s/status", id)'

      expect(literal_caller?("/api/v1/system/node_api/storage_assignments/:id/status", text)).to be(true)
    end

    it "scans the worker and the Go agent trees, but not their tests" do
      dirs = RouteCallerCoverageChecker::SERVICE_DIRS
      expect(dirs).to include("worker/app/jobs", "worker/app/services", "extensions/system/agent")
      expect(dirs).not_to include("worker/app/controllers")
      expect(RouteCallerCoverageChecker.caller_source_file?("/x/worker/app/jobs/a_job.rb")).to be(true)
      expect(RouteCallerCoverageChecker.caller_source_file?("/x/agent/internal/y/client.go")).to be(true)
      expect(RouteCallerCoverageChecker.caller_source_file?("/x/agent/internal/y/client_test.go")).to be(false)
      expect(RouteCallerCoverageChecker.caller_source_file?("/x/agent/internal/y/client.py")).to be(false)
    end

    it "builds the server-side corpus through caller_source_file?, so the tested filter is the real one" do
      files = RouteCallerCoverageChecker.send(:service_file_index).keys

      expect(files).not_to be_empty
      expect(files).to all(satisfy { |f| RouteCallerCoverageChecker.caller_source_file?(f) })
      expect(files.grep(/_test\.go\z|_spec\.rb\z/)).to be_empty
      expect(files.grep(%r{/worker/app/jobs/})).not_to be_empty
    end

    it "does not count a whole-line Go or Ruby comment as a caller" do
      checker = RouteCallerCoverageChecker
      go = "//   - Otherwise, POSTs to <parent_url>/api/v1/system/federation_api/accept\n"
      rb = "  # calls /api/v1/admin/daily_summaries/generate nightly\n"
      interp = "  \#{base}/api/v1/admin/daily_summaries/generate\n"

      expect(checker.send(:strip_comment_lines, go)).to eq("")
      expect(checker.send(:strip_comment_lines, rb)).to eq("")
      expect(checker.send(:strip_comment_lines, interp)).to eq(interp)
    end

    it "credits a route only the worker calls" do
      route = RouteCallerCoverageChecker.non_internal_api_v1_routes.find do |r|
        r.key == "api/v1/admin/daily_summaries#generate"
      end

      expect(route).not_to be_nil
      expect(RouteCallerCoverageChecker.covered?(route)).to be(true)
    end

    it "credits the real callers these shapes used to miss" do
      routes = RouteCallerCoverageChecker.non_internal_api_v1_routes.index_by(&:key)

      %w[
        api/v1/audit_logs#security_summary
        api/v1/ai/agent_intelligence#experience_replays
        api/v1/ai/coordination_dashboard#pressure_fields
        api/v1/ai/coordination_dashboard#team_events
        api/v1/ai/governance_reports#collusion_indicators
        api/v1/devops/overview#show
        api/v1/ai/execution_traces#show
      ].each do |key|
        expect(routes).to have_key(key)
        expect(RouteCallerCoverageChecker.covered?(routes[key])).to be(true), "#{key} should read as covered"
      end
    end
  end

  # Review round 1 (MED): the baseline is a ONE-WAY RATCHET — it may shrink
  # (a route gets a real caller, or is deleted) but must never silently grow,
  # and it must never keep citing a route that has already moved on. Every
  # example here refuses to offer "add it to the baseline" as the fix,
  # because the entry is ALREADY there — the fix is a caller or a deletion.
  describe "baseline hygiene (one-way ratchet)" do
    let(:current_route_keys) do
      RouteCallerCoverageChecker.non_internal_api_v1_routes.map(&:key).to_set
    end

    let(:current_routes_by_key) do
      RouteCallerCoverageChecker.non_internal_api_v1_routes.index_by(&:key)
    end

    it "flags a baseline entry for a route that no longer exists or is now covered" do
      stale = baseline_allowlist.select do |key|
        route = current_routes_by_key[key]
        route.nil? || RouteCallerCoverageChecker.covered?(route)
      end

      expect(stale).to be_empty, <<~MSG
        #{stale.size} baseline entr#{stale.size == 1 ? 'y is' : 'ies are'} stale — the route
        no longer exists, or now has a real caller. Remove this line from the baseline
        (and lower MAX_BASELINE_SIZE to match):

        #{stale.sort.join("\n")}
      MSG
    end

    it "flags a WEBHOOK_ALLOWLIST key that does not name a currently-mounted route" do
      unknown = WEBHOOK_ALLOWLIST.keys.reject { |key| current_route_keys.include?(key) }

      expect(unknown).to be_empty, <<~MSG
        WEBHOOK_ALLOWLIST names route(s) that are not mounted. Remove the allowlist
        entry; a webhook entry for a route that isn't mounted proves nothing:

        #{unknown.sort.join("\n")}
      MSG
    end

    it "requires every PENDING_DECISION entry to name an offer and a reason" do
      expect(PENDING_DECISION).not_to be_empty
      incomplete = PENDING_DECISION.reject do |_key, entry|
        entry[:offer].to_s.match?(/\A\h{8}\z/) && entry[:reason].to_s.strip.present?
      end
      expect(incomplete).to be_empty, "PENDING_DECISION entries missing an offer id or reason: #{incomplete.keys.join(', ')}"
    end

    it "flags a PENDING_DECISION entry whose route is gone or now has a caller" do
      stale = PENDING_DECISION.keys.select do |key|
        route = current_routes_by_key[key]
        route.nil? || RouteCallerCoverageChecker.covered?(route)
      end

      expect(stale).to be_empty, <<~MSG
        PENDING_DECISION entries whose route no longer exists or now has a caller —
        the decision has been made; remove the entry:

        #{stale.sort.join("\n")}
      MSG
    end

    it "never lists a route on both PENDING_DECISION and the baseline" do
      expect(PENDING_DECISION.keys & baseline_allowlist.to_a).to be_empty
    end

    it "keeps the baseline exactly at its committed size" do
      expect(baseline_allowlist.size).to eq(MAX_BASELINE_SIZE), <<~MSG
        baseline_allowlist.txt has #{baseline_allowlist.size} entries; MAX_BASELINE_SIZE
        is #{MAX_BASELINE_SIZE}. If it shrank, lower MAX_BASELINE_SIZE to match. If it
        grew, add a caller or delete the route instead — the baseline takes no new entries.
      MSG
    end
  end
end
