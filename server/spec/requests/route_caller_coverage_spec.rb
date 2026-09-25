# frozen_string_literal: true

require "rails_helper"

# fc-27 — Route caller coverage guard.
#
# Every non-internal api/v1 route (any controller NOT under
# Api::V1::Internal::*, which is service-token-authed worker traffic that by
# design has no frontend/MCP caller) must have EITHER:
#   - a frontend literal caller (core + public/private extension frontend), or
#   - an MCP-tool / extension-service caller, or
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
# a NEW zero-caller route, not to re-litigate the existing 750).
RSpec.describe "Route caller coverage", type: :routing do
  # One-way ratchet: the baseline may shrink (a route gets a caller, or is
  # deleted) but must never silently grow. Bumping this is a deliberate,
  # reviewed diff — never a side effect of adding a route with no caller.
  MAX_BASELINE_SIZE = 750
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
        baseline_allowlist.include?(route.key) ||
        RouteCallerCoverageChecker.covered?(route)
    end

    expect(new_hits).to be_empty, <<~MSG
      #{new_hits.size} route(s) have no frontend/MCP-tool caller and are not on the
      webhook allowlist or the pre-existing baseline:

      #{new_hits.map(&:key).sort.join("\n")}

      For each: wire a real caller, add a reasoned entry to WEBHOOK_ALLOWLIST above
      (inbound receivers ONLY), or — if it's pre-existing and genuinely out of this
      change's scope — add it to spec/fixtures/route_caller_coverage/baseline_allowlist.txt.
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
        no longer exists, or now has a real caller. Add a caller or delete the route;
        do not leave a stale line in the baseline:

        #{stale.sort.join("\n")}
      MSG
    end

    it "flags a WEBHOOK_ALLOWLIST key that does not name a currently-mounted route" do
      unknown = WEBHOOK_ALLOWLIST.keys.reject { |key| current_route_keys.include?(key) }

      expect(unknown).to be_empty, <<~MSG
        WEBHOOK_ALLOWLIST names route(s) that no longer exist. Add a caller or delete
        the route; a webhook entry for a route that isn't mounted proves nothing:

        #{unknown.sort.join("\n")}
      MSG
    end

    it "keeps the baseline at or below its committed ceiling" do
      expect(baseline_allowlist.size).to be <= MAX_BASELINE_SIZE, <<~MSG
        baseline_allowlist.txt has #{baseline_allowlist.size} entries, over the
        committed ceiling of #{MAX_BASELINE_SIZE}. Add a caller or delete the route —
        growing the baseline is not an option this guard offers; raising the ceiling
        constant is a separate, deliberately reviewed decision.
      MSG
    end
  end
end
