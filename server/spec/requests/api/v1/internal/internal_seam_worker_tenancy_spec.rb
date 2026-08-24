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
    }
  ].freeze

  # The controllers this sweep is required to cover. If a CASE is dropped, this
  # list stops matching and the guard example below fails by name — the sweep
  # cannot be silently narrowed.
  REQUIRED_CONTROLLERS = %w[
    internal/git/credentials#decrypted
    internal/git/credentials#show
    internal/mcp_servers#show
    internal/mcp_tool_executions#show
    internal/devops/docker#connection
    internal/devops/swarm#connection
    internal/approval_tokens#show
  ].freeze

  it "keeps a tenancy case for every required internal controller lookup" do
    covered = CASES.map { |c| c[:name].split(" ").first }
    REQUIRED_CONTROLLERS.each do |ctrl|
      expect(covered).to include(ctrl),
        "no cross-account tenancy case covers #{ctrl} — the sweep was narrowed"
    end
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
        end
      end

      context "the SYSTEM worker reaching account B's record" do
        it "is denied too (its CN is a published constant)" do
          rec_b = kase[:build].call(account_b, sentinel_b)

          kase[:request].call(self, system_worker, rec_b)

          expect(response).to have_http_status(:not_found)
          expect(response.body).not_to include(sentinel_b)
        end
      end

      context "POSITIVE CONTROL: the worker reaching its OWN account's record" do
        it "still resolves the record and returns its material" do
          rec_a = kase[:build].call(account_a, sentinel_a)

          kase[:request].call(self, worker_a, rec_a)

          expect(response).not_to have_http_status(:not_found)
          expect(response.body).to include(sentinel_a)
        end
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
