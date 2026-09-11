# frozen_string_literal: true

require "rails_helper"

# Namespace-wide cross-account tenancy sweep for the worker→server internal
# seam (`/api/v1/internal/**`), authenticated by
# InternalBaseController#authenticate_worker_via_mtls!.
#
# WHY THIS EXISTS. Two earlier fixes (e9352723d, 0f4b6e1db) scoped the worker
# lookups in `internal/ai/*` to the calling worker's account, but the SAME
# pattern — load a tenant row by bare, caller-supplied id — survived untouched
# in six more controllers, each disclosing (or minting against) another
# account's secrets by enumerable id. This spec enumerates the sensitive
# lookups on the seam and asserts each one is anchored, so the class cannot
# quietly regenerate in a third place: dropping the anchor from a controller
# fails a NAMED example here.
#
# ORACLE = CROSS-TENANT ACCESS, NOT STATUS ALONE. Where a body carries secret
# material the example asserts the sentinel is ABSENT from the body (a 200 with
# the victim's key in it IS the disclosure). A cross-account lookup must 404,
# never 403 — a 403 confirms the row exists on another account, itself a
# disclosure. Fetch helpers are `def`s, never `let`s: a memoizing helper would
# issue one request and replay it, silently passing against unfixed code.
#
# NO is_system EXEMPTION. The principal is a Worker resolved from the forwarded
# client-cert CN and is account-bound in production (worker_provision.rake
# leaves is_system false). The system worker's CN can be the PUBLISHED constant
# EnsureSystemWorker::DEV_SENTINEL_NODE_ID, so it is DENIED cross-account too;
# see Api::V1::Internal::WorkerTenancy.
RSpec.describe "Internal seam cross-account worker tenancy", type: :request do
  # --- principals -----------------------------------------------------------
  let(:account_a) { FactoryBot.create(:account) }
  let(:account_b) { FactoryBot.create(:account) }
  let(:worker_a)  { FactoryBot.create(:worker, account: account_a, status: "active") }
  let(:system_worker) { FactoryBot.create(:worker, :system_worker, account: account_a, status: "active") }

  def headers_for(worker)
    {
      "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
      "Content-Type" => "application/json"
    }
  end

  def ids_in_body
    response.body.scan(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i).map(&:downcase)
  end

  # The integration_health#probe case runs a connection test on the POSITIVE
  # control. Stubbed at that one external boundary so the sweep never opens a
  # socket; no other case calls it.
  before do
    allow(Devops::ExecutionService).to receive(:test_connection)
      .and_return({ success: true, message: "ok", tested_at: Time.current })
  end

  # ==========================================================================
  # DECLARATIVE ENUMERATION of the seam's secret-bearing lookups.
  #
  # Each case names its controller#action, builds a record under a given
  # account carrying a recognisable sentinel, and issues the request as a given
  # worker. `build` returns the record; `sentinel` is embedded in it and must
  # never cross tenants; `request` performs the call for (worker, record).
  # ==========================================================================
  CASES = [
    {
      name: "internal/git/credentials#decrypted (PLAINTEXT git token)",
      build: ->(account, sentinel) {
        FactoryBot.create(:git_provider_credential, account: account,
               credentials: { "access_token" => sentinel })
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/git/credentials/#{rec.id}/decrypted",
          headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/git/credentials#show",
      build: ->(account, sentinel) {
        FactoryBot.create(:git_provider_credential, account: account, name: sentinel,
               credentials: { "access_token" => "unused-#{SecureRandom.hex(4)}" })
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/git/credentials/#{rec.id}", headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/mcp_servers#show (mcp_server.env)",
      build: ->(account, sentinel) {
        FactoryBot.create(:mcp_server, account: account, env: { "SECRET_KEY" => sentinel })
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/mcp_servers/#{rec.id}", headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/mcp_tool_executions#show (nested mcp_server.env, config requested)",
      build: ->(account, sentinel) {
        server = FactoryBot.create(:mcp_server, account: account, env: { "SECRET_KEY" => sentinel })
        tool   = FactoryBot.create(:mcp_tool, mcp_server: server)
        FactoryBot.create(:mcp_tool_execution, mcp_tool: tool)
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/mcp_tool_executions/#{rec.id}?include_server_config=true",
          headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/devops/docker#connection (encrypted_tls_credentials)",
      build: ->(account, sentinel) {
        FactoryBot.create(:devops_docker_host, account: account,
               encrypted_tls_credentials: sentinel, encryption_key_id: "key-#{SecureRandom.hex(4)}")
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/devops/docker/hosts/#{rec.id}/connection",
          headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/devops/swarm#connection (cluster encrypted_tls_credentials)",
      build: ->(account, sentinel) {
        FactoryBot.create(:devops_swarm_cluster, account: account,
               encrypted_tls_credentials: sentinel, encryption_key_id: "key-#{SecureRandom.hex(4)}")
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/devops/swarm/clusters/#{rec.id}/connection",
          headers: ctx.headers_for(worker)
      }
    },
    {
      # A8 (component status plane). The probe endpoint MUTATES the row it
      # resolves — it writes the health columns and can auto-pause — so an
      # unanchored lookup here would be a cross-account WRITE, not just a read.
      name: "internal/devops/integration_health#probe (mutates the resolved row)",
      build: ->(account, sentinel) {
        FactoryBot.create(:devops_integration_instance, account: account,
               name: sentinel, slug: sentinel.downcase, status: "active")
      },
      request: ->(ctx, worker, rec) {
        ctx.post "/api/v1/internal/devops/integration_health/#{rec.id}/probe",
          headers: ctx.headers_for(worker)
      }
    },
    {
      name: "internal/approval_tokens#show (foreign pipeline step details)",
      build: ->(account, sentinel) {
        pipeline = FactoryBot.create(:devops_pipeline, account: account)
        run  = FactoryBot.create(:devops_pipeline_run, pipeline: pipeline)
        step = FactoryBot.create(:devops_pipeline_step, pipeline: pipeline, name: sentinel)
        FactoryBot.create(:devops_step_execution, pipeline_run: run, pipeline_step: step)
      },
      request: ->(ctx, worker, rec) {
        ctx.get "/api/v1/internal/approval_tokens/#{rec.id}", headers: ctx.headers_for(worker)
      }
    },
    {
      # Goal plans (review B-1). The action FAILS the step it resolves, so an
      # unanchored lookup here is a cross-account WRITE. Its response carries
      # no record material a sentinel could ride in, so the oracle is the ROW
      # (`mutated`): a foreign step must be left untouched, and the worker's own
      # fresh executing step must be failed.
      name: "internal/ai/goal_plans#execute_step (fails the resolved step)",
      build: ->(account, sentinel) {
        agent = FactoryBot.create(:ai_agent, account: account)
        goal = ::Ai::AgentGoal.create!(account: account, agent: agent, title: sentinel,
                                       goal_type: "improvement", status: "active", priority: 3, progress: 0)
        plan = ::Ai::GoalPlan.create!(account: account, goal: goal, agent: agent, status: "executing", version: 1)
        ::Ai::GoalPlanStep.create!(plan: plan, step_number: 1, status: "executing",
                                   step_type: "agent_execution", description: sentinel)
      },
      request: ->(ctx, worker, rec) {
        ctx.post "/api/v1/internal/ai/goal_plans/execute_step", params: { step_id: rec.id }.to_json,
                                                              headers: ctx.headers_for(worker)
      },
      mutated: ->(rec) { rec.reload.status == "failed" }
    }
  ].freeze

  # WHICH DOORS THIS SWEEP MUST COVER. Two sources, because a router can say
  # which doors WRITE but not which reads DISCLOSE:
  #
  # - READ doors, kept by hand (.required_read_doors): GETs that return secret
  #   material or a foreign record. A new sensitive read gets a line there and
  #   a CASE.
  # - WRITE doors, DERIVED from the router when the example runs
  #   (.internal_mutating_doors): every POST/PUT/PATCH/DELETE route under
  #   /api/v1/internal/, mounted engines included. These were hand-kept too
  #   until 2026-09-11, and three doors (improvement_discovery#run and
  #   #timed_out, campaign_discovery#scan) shipped without WorkerTenancy
  #   because nobody added them to the list. A derived list cannot forget a
  #   door: a new mutating internal route is REQUIRED the moment it is drawn,
  #   and fails the guard below until it has a tenancy case.
  #
  # A write door with no tenancy case YET is named in
  # internal_seam_worker_tenancy_baseline.yml, which only shrinks (the ratchet
  # example below). The required set is the read doors plus every derived
  # write door that baseline does not name.
  #
  # Class methods, not constants: a constant assigned in a describe block lands
  # on Object, and the derivation must read the router when the example runs,
  # not when this file loads.
  def self.required_read_doors
    %w[
      internal/git/credentials#decrypted
      internal/git/credentials#show
      internal/mcp_servers#show
      internal/mcp_tool_executions#show
      internal/devops/docker#connection
      internal/devops/swarm#connection
      internal/approval_tokens#show
    ].freeze
  end

  # POSITIONAL doors. The caller names a POSITION in a walk of accounts, not a
  # row id, so the CASES shape (fetch a foreign id, expect a 404) does not
  # fit: a foreign account is reached by walking to its position. Each door
  # WRITES onto the account at the position it is given (a discovery run
  # record, and on #run a dispatch that leases that account's runner), so the
  # oracle is the ROW, never the status: after the worker walks every position
  # the GLOBAL walk has, account B must have gained no run record and no
  # dispatch, and the worker's own account must still have gained both.
  WALK_CASES = [
    { name: "internal/ai/improvement_discovery#run (dispatches and records the unit's account)",
      path: "/api/v1/internal/ai/improvement_discovery/run", dispatches: true },
    { name: "internal/ai/improvement_discovery#timed_out (records the unit's account)",
      path: "/api/v1/internal/ai/improvement_discovery/timed_out", dispatches: false }
  ].freeze

  # ACCOUNT-SWEEP doors. One call walks accounts on the server's side, with no
  # id and no position from the caller, and writes onto each account it walks.
  # The oracle is the ROW: account B must gain nothing from a call by a worker
  # bound to account A, and account A must still gain its own rows.
  SWEEP_CASES = [
    { name: "internal/ai/campaign_discovery#scan (writes campaign proposals onto each account it scans)" }
  ].freeze

  # Every mutating route under /api/v1/internal/ as "<controller>#<action>",
  # named the way the cases below name their door, descending into mounted
  # engines so an extension's internal door is required too.
  def self.internal_mutating_doors(routes = Rails.application.routes.routes, prefix = "")
    routes.flat_map do |route|
      app = route.app.respond_to?(:app) ? route.app.app : route.app
      path = prefix + route.path.spec.to_s
      if app.respond_to?(:routes) && app != Rails.application
        internal_mutating_doors(app.routes.routes, path.delete_suffix("(.:format)"))
      elsif path.include?("/api/v1/internal/") && route.defaults[:controller] && route.defaults[:action] &&
            route.verb.to_s.split("|").any? { |verb| verb.match?(/\A(POST|PUT|PATCH|DELETE)\z/) }
        [ "#{route.defaults[:controller].delete_prefix('api/v1/')}##{route.defaults[:action]}" ]
      else
        []
      end
    end.uniq
  end

  # The doors this file HAS a tenancy case for, read from its own example
  # groups (each case's describe is named "<door> (<what it guards>)"), so the
  # coverage cannot drift from the examples that exist.
  def self.covered_doors
    children.map { |group| group.description.split(" ").first.to_s }
            .select { |token| token.include?("#") }
            .map { |token| token.start_with?("internal/") ? token : "internal/#{token}" }
            .uniq
  end

  def self.uncovered_baseline
    YAML.safe_load_file(File.expand_path("internal_seam_worker_tenancy_baseline.yml", __dir__)).fetch("uncovered")
  end

  # The baseline's size, pinned. It only goes DOWN: a new mutating door gets a
  # tenancy case, never a baseline line. Lower it in the same change that
  # clears an entry; the ratchet example fails until you do.
  def self.uncovered_ceiling = 182

  def self.required_doors
    required_read_doors + (internal_mutating_doors - uncovered_baseline)
  end

  it "keeps a tenancy case for every required internal door" do
    missing = self.class.required_doors - self.class.covered_doors
    expect(missing).to be_empty,
      "no cross-account tenancy case covers #{missing.join(', ')} — add a CASE, WALK_CASE or SWEEP_CASE. " \
      "A mutating internal door is required the moment it is routed; it never goes in the baseline"
  end

  it "derives the write doors from the router: a covered door and a baselined door are both seen, a read is not" do
    doors = self.class.internal_mutating_doors
    expect(doors).to include("internal/ai/goal_plans#execute_step", "internal/ai/ralph_loops#run_iteration")
    expect(doors).not_to include("internal/git/credentials#decrypted")
  end

  it "baselines exactly the write doors that have no tenancy case yet, and the baseline only shrinks" do
    uncovered = self.class.internal_mutating_doors - self.class.covered_doors
    baseline = self.class.uncovered_baseline
    stale = baseline - uncovered
    expect(stale).to be_empty,
      "baseline entries that now have a tenancy case, or whose route is gone: delete them and lower " \
      "uncovered_ceiling — #{stale.join(', ')}"
    expect(baseline).to eq(baseline.uniq)
    expect(baseline.size).to eq(self.class.uncovered_ceiling),
      "the baseline names #{baseline.size} doors but uncovered_ceiling is #{self.class.uncovered_ceiling}: " \
      "lower the ceiling to match; never raise it"
  end

  describe "authentication sanity" do
    it "resolves the forwarded CN (otherwise every denial below is vacuous)" do
      rec = CASES.first[:build].call(account_a, "auth-sanity-#{SecureRandom.hex(4)}")
      CASES.first[:request].call(self, worker_a, rec)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  CASES.each do |kase|
    describe kase[:name] do
      let(:sentinel_b) { "SENTINEL-B-#{SecureRandom.hex(8)}-must-never-leak" }
      let(:sentinel_a) { "SENTINEL-A-#{SecureRandom.hex(8)}-legitimate" }

      context "an ACCOUNT-BOUND worker reaching account B's record" do
        it "404s and discloses no part of the foreign record" do
          rec_b = kase[:build].call(account_b, sentinel_b)

          kase[:request].call(self, worker_a, rec_b)

          expect(response).to have_http_status(:not_found)
          expect(response.body).not_to include(sentinel_b)
          expect(ids_in_body).not_to include(rec_b.id.to_s.downcase)
          # A mutating case: the foreign row must also be left untouched.
          expect(kase[:mutated].call(rec_b)).to be(false) if kase[:mutated]
        end
      end

      context "the SYSTEM worker reaching account B's record" do
        it "is denied too (its CN is a published constant)" do
          rec_b = kase[:build].call(account_b, sentinel_b)

          kase[:request].call(self, system_worker, rec_b)

          expect(response).to have_http_status(:not_found)
          expect(response.body).not_to include(sentinel_b)
          expect(kase[:mutated].call(rec_b)).to be(false) if kase[:mutated]
        end
      end

      context "POSITIVE CONTROL: the worker reaching its OWN account's record" do
        it "still resolves the record and returns its material" do
          rec_a = kase[:build].call(account_a, sentinel_a)

          kase[:request].call(self, worker_a, rec_a)

          expect(response).not_to have_http_status(:not_found)
          # A mutating case proves resolution by the row it changed, since its
          # response carries no record material; the rest by the body.
          if kase[:mutated]
            expect(kase[:mutated].call(rec_a)).to be(true)
          else
            expect(response.body).to include(sentinel_a)
          end
        end
      end
    end
  end

  WALK_CASES.each do |kase|
    describe kase[:name] do
      # The account ids the stand-in discovery executor was handed.
      let(:dispatched) { [] }

      before do
        FactoryBot.create(:git_repository, account: account_a)
        FactoryBot.create(:git_repository, account: account_b)
        calls = dispatched
        executor = Object.new.tap do |stand_in|
          stand_in.define_singleton_method(:dispatch!) do |account:, repositories:|
            calls << account.id
            { status: "dispatched", run_ref: "lease-#{account.id}",
              repositories: repositories.map { |repo| { id: repo.id, status: "dispatched" } } }
          end
        end
        allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
        allow(Powernode::ExtensionRegistry).to receive(:provider)
          .with(::Ai::Improvement::DiscoveryRunService::EXECUTOR_KEY).and_return(executor)
      end

      def run_records(account)
        AuditLog.where(action: "ai.improvement_discovery.run", account_id: account.id).count
      end

      # Every position of the GLOBAL walk, plus one past its end, so a door
      # that still indexes every account reaches account B's unit.
      def walk_every_position(worker, path)
        (0..::Ai::Improvement::DiscoveryRunService.units(::Account.all).size).each do |position|
          post path, params: { position: position }.to_json, headers: headers_for(worker)
        end
      end

      context "an ACCOUNT-BOUND worker walking every position" do
        it "writes no run record onto account B and dispatches nothing for it" do
          account_b # the foreign account exists before the walk is sized

          expect { walk_every_position(worker_a, kase[:path]) }.not_to change { run_records(account_b) }
          expect(dispatched).not_to include(account_b.id)
        end
      end

      context "the SYSTEM worker walking every position" do
        it "is confined too (its CN is a published constant)" do
          account_b

          expect { walk_every_position(system_worker, kase[:path]) }.not_to change { run_records(account_b) }
          expect(dispatched).not_to include(account_b.id)
        end
      end

      context "POSITIVE CONTROL: the worker's walk reaches its OWN account" do
        it "records its own account's unit" do
          account_b

          expect { walk_every_position(worker_a, kase[:path]) }.to change { run_records(account_a) }.by_at_least(1)
          expect(dispatched).to include(account_a.id) if kase[:dispatches]
        end
      end
    end
  end

  describe SWEEP_CASES.first[:name] do
    # One pending recommendation on a target is a backlog worth one proposal.
    def seed_backlog(account)
      FactoryBot.create(:ai_improvement_recommendation, account: account, status: "pending",
                                                        target_type: "Devops::GitRepository", target_id: SecureRandom.uuid)
    end

    def scan(worker)
      post "/api/v1/internal/ai/campaign_discovery/scan", headers: headers_for(worker)
    end

    def proposals(account) = ::Ai::CampaignProposal.where(account_id: account.id).count

    before do
      seed_backlog(account_a)
      seed_backlog(account_b)
    end

    context "an ACCOUNT-BOUND worker's scan" do
      it "writes no campaign proposal onto account B" do
        expect { scan(worker_a) }.not_to change { proposals(account_b) }
        expect(response).to have_http_status(:ok)
      end
    end

    context "the SYSTEM worker's scan" do
      it "is confined too (its CN is a published constant)" do
        expect { scan(system_worker) }.not_to change { proposals(account_b) }
      end
    end

    context "POSITIVE CONTROL: the worker's scan reaches its OWN account" do
      it "writes account A's proposal" do
        expect { scan(worker_a) }.to change { proposals(account_a) }.from(0).to(1)
      end
    end
  end

  # ==========================================================================
  # mcp_tool_executions#show — over-disclosure oracle (offer 01a02aac-b6f9
  # DEFECT 2): the nested mcp_server.env must be ABSENT from the DEFAULT
  # representation, present only when explicitly requested. This is the oracle
  # that a reviewer treating this as a duplicate of the mcp_servers offer would
  # skip, so it is filed on its own.
  # ==========================================================================
  describe "mcp_tool_executions#show env is opt-in, not default" do
    def show_execution(worker, execution, query = "")
      get "/api/v1/internal/mcp_tool_executions/#{execution.id}#{query}",
        headers: headers_for(worker)
    end

    let(:sentinel) { "ENV-SENTINEL-#{SecureRandom.hex(8)}" }
    let(:execution) do
      server = FactoryBot.create(:mcp_server, account: account_a, env: { "SECRET_KEY" => sentinel })
      tool = FactoryBot.create(:mcp_tool, mcp_server: server)
      FactoryBot.create(:mcp_tool_execution, mcp_tool: tool)
    end

    it "omits nested server env by default even for the owning worker" do
      show_execution(worker_a, execution)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(sentinel)
    end

    it "includes nested server env when the owning worker explicitly requests it" do
      show_execution(worker_a, execution, "?include_server_config=true")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(sentinel)
    end
  end

  # ==========================================================================
  # approval_tokens#create_tokens — the highest-blast-radius offer
  # (01a02aac-195e): an AUTHORIZATION BYPASS, not a disclosure. Two defects,
  # each with its own oracle.
  # ==========================================================================
  describe "approval_tokens#create_tokens" do
    def create_tokens(worker, step_execution, recipients)
      post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
        params: { recipients: recipients }.to_json, headers: headers_for(worker)
    end

    def step_execution_for(account, approver_email)
      pipeline = FactoryBot.create(:devops_pipeline, account: account)
      run  = FactoryBot.create(:devops_pipeline_run, pipeline: pipeline)
      step = FactoryBot.create(:devops_pipeline_step, pipeline: pipeline,
        requires_approval: true,
        approval_settings: {
          "timeout_hours" => 24,
          "notification_recipients" => [ { "type" => "email", "value" => approver_email } ]
        })
      FactoryBot.create(:devops_step_execution, pipeline_run: run, pipeline_step: step)
    end

    # DEFECT 1 — cross-account mint. Oracle is ABSENCE OF EFFECT, not status: a
    # spec asserting only 404 would pass against code that 404s AFTER minting.
    context "cross-account (worker A minting against account B's step)" do
      it "creates NO token for the foreign step and returns no raw_token" do
        step_b = step_execution_for(account_b, "victim-approver@example.com")

        expect {
          create_tokens(worker_a, step_b, [ { "value" => "attacker@evil.example" } ])
        }.not_to change(::Devops::StepApprovalToken, :count)

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("raw_token")
      end
    end

    # DEFECT 2 — caller-supplied recipients. Even correctly scoped, the token's
    # recipient must derive from the step's own configured policy, never from
    # the request body, or a caller mints itself an approver.
    context "in-account with an attacker-supplied recipient list" do
      it "ignores the body and mints only for the step's configured approver" do
        approver = "configured-approver@example.com"
        step_a = step_execution_for(account_a, approver)

        create_tokens(worker_a, step_a, [ { "value" => "attacker@evil.example" } ])

        expect(response).to have_http_status(:ok)
        tokens = step_a.reload.approval_tokens
        expect(tokens.map(&:recipient_email)).to eq([ approver ])
        expect(tokens.map(&:recipient_email)).not_to include("attacker@evil.example")
      end
    end

    # POSITIVE CONTROL: the legitimate path still mints a usable token in-band
    # (the worker needs raw_token to send the approval email).
    context "POSITIVE CONTROL: legitimate in-account mint" do
      it "mints a token for the configured approver and returns raw_token" do
        approver = "configured-approver@example.com"
        step_a = step_execution_for(account_a, approver)

        expect {
          create_tokens(worker_a, step_a, [])
        }.to change(::Devops::StepApprovalToken, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        token = body.dig("data", "tokens").first
        expect(token["recipient_email"]).to eq(approver)
        expect(token["raw_token"]).to be_present
      end
    end
  end
  # ==========================================================================
  # devops/{docker,swarm}#create_event cleanup — cross-tenant DESTRUCTIVE
  # bypass (found in independent review). The cleanup branch delete_all'd
  # acknowledged events with a caller-controlled retention window and NO
  # account anchor, so a forged worker could purge every tenant's event
  # history. Oracle is ABSENCE OF EFFECT: account B's events must survive a
  # worker A cleanup, even with a negative (purge-everything) window.
  # ==========================================================================
  describe "devops/docker#create_event cleanup is account-scoped" do
    def cleanup(worker, older_than_days)
      post "/api/v1/internal/devops/docker/events",
        params: { action_type: "cleanup", older_than_days: older_than_days }.to_json,
        headers: headers_for(worker)
    end

    it "does not delete another account's acknowledged events" do
      host_b = FactoryBot.create(:devops_docker_host, account: account_b)
      event_b = FactoryBot.create(:devops_docker_event, :acknowledged, docker_host: host_b)

      cleanup(worker_a, -1) # -1 day window => purge-everything, if unscoped

      expect(response).to have_http_status(:ok)
      expect(::Devops::DockerEvent.exists?(event_b.id)).to be(true)
    end

    it "POSITIVE CONTROL: still deletes the worker's OWN acknowledged events" do
      host_a = FactoryBot.create(:devops_docker_host, account: account_a)
      event_a = FactoryBot.create(:devops_docker_event, :acknowledged, docker_host: host_a)

      cleanup(worker_a, -1)

      expect(response).to have_http_status(:ok)
      expect(::Devops::DockerEvent.exists?(event_a.id)).to be(false)
    end
  end

  describe "devops/swarm#create_event cleanup is account-scoped" do
    def cleanup(worker, older_than_days)
      post "/api/v1/internal/devops/swarm/events",
        params: { action_type: "cleanup", older_than_days: older_than_days }.to_json,
        headers: headers_for(worker)
    end

    def acknowledged_swarm_event(cluster)
      cluster.swarm_events.create!(
        event_type: "health_check", severity: "info", source_type: "cluster",
        message: "evt #{SecureRandom.hex(3)}", acknowledged: true, acknowledged_at: Time.current
      )
    end

    it "does not delete another account's acknowledged events" do
      cluster_b = FactoryBot.create(:devops_swarm_cluster, account: account_b)
      event_b = acknowledged_swarm_event(cluster_b)

      cleanup(worker_a, -1)

      expect(response).to have_http_status(:ok)
      expect(::Devops::SwarmEvent.exists?(event_b.id)).to be(true)
    end

    it "POSITIVE CONTROL: still deletes the worker's OWN acknowledged events" do
      cluster_a = FactoryBot.create(:devops_swarm_cluster, account: account_a)
      event_a = acknowledged_swarm_event(cluster_a)

      cleanup(worker_a, -1)

      expect(response).to have_http_status(:ok)
      expect(::Devops::SwarmEvent.exists?(event_a.id)).to be(false)
    end
  end
end
