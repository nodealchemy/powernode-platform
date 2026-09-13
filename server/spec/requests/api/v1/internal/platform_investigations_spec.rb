# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — the worker→server door for
# investigation ranking (design §5.3).
RSpec.describe "Api::V1::Internal platform investigation conclude", type: :request do
  let(:account) { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  let(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: Platform::ComponentStatus::DOWN,
                                       conditions: [ { "type" => "Connected", "status" => false,
                                                       "reason" => "ConnectionError", "severity" => "down" } ])
  end

  # Opened by a person, as the drawer and the MCP verb open one. Ranking
  # spends only as the opener, and an investigation with no opener is refused
  # before the gate (A6 re-review), so every ranking example here needs one.
  let(:operator) { create(:user, account: account) }
  let(:investigation) do
    Platform::InvestigationService.new(account: account)
                                  .open!(component, trigger: "operator", opened_by: operator)[:investigation]
  end

  def post_conclude(id, headers: worker_headers)
    post "/api/v1/internal/platform/investigations/#{id}/conclude",
         params: {}.to_json,
         headers: headers.merge("Content-Type" => "application/json")
  end

  def body = JSON.parse(response.body)

  # THE STUB IS AT THE PROVIDER BOUNDARY, NOT AT THE EXECUTOR.
  #
  # This used to replace `Ai::McpAgentExecutor` with an `instance_double`
  # returning `{output: text}` — a shape the executor never returns. A total
  # double of a collaborator cannot catch a contract mismatch WITH that
  # collaborator, and `instance_double` verifies only the signature of
  # `execute`, never the shape of what it returns. So the spec enforced the bug
  # rather than catching it, and every real ranking failed while all 17
  # examples stayed green.
  #
  # Stubbing `execute_with_provider` leaves the real executor running,
  # including `format_mcp_response`, which is what nests the provider's text
  # under "result". The gates are stubbed because they are not what these
  # examples are about; F3's example covers the principal, and the security
  # gate is flagged separately in the report.
  def stub_ranker(text)
    agent = create(:ai_agent, account: account)
    allow(Platform::Investigation::Ranking).to receive(:agent_for).and_return(agent)
    stub_provider(text)
    agent
  end

  def stub_provider(text)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
      .and_return("output" => text, "metadata" => { "tokens_used" => 10 })
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_pre_execution_security_gate).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails).and_return(blocked: false)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_post_execution_security_gate).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_output_guardrails).and_return(blocked: false)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:validate_output!).and_return(true)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:write_back_to_memory).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:record_security_telemetry).and_return(nil)
  end

  before { system_worker }

  describe "authentication" do
    it "refuses a request with no worker mTLS identity" do
      post_conclude(investigation.id, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the worker's mTLS identity — the other arm" do
      stub_ranker('{"hypotheses":[]}')

      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the lookup" do
    it "404s an id that does not exist" do
      post_conclude(SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
    end

    it "reaches a shared investigation, which belongs to no tenant" do
      shared_component = create(:platform_component_status, :shared,
                                component_kind: "provider_circuit_breaker", component_ref: "breaker-1",
                                verdict: Platform::ComponentStatus::DEGRADED,
                                conditions: [ { "type" => "Closed", "status" => false,
                                                "reason" => "BreakerOpen", "severity" => "degraded" } ])
      shared = Platform::InvestigationService.new(account: nil)
                                             .open!(shared_component, trigger: "operator")[:investigation]
      stub_ranker('{"hypotheses":[]}')

      post_conclude(shared.id)

      expect(response).to have_http_status(:ok)
    end
  end

  # THERE IS EXACTLY ONE SYSTEM WORKER, platform-wide, and it belongs to one
  # account (`Worker#only_one_system_worker_globally`). It runs the ranking job
  # for every tenant, so it must reach every tenant's investigation. This door
  # used to anchor it on its own account, which 404'd every OTHER tenant's
  # investigation — the job raised, retried, and the row stayed open forever.
  # The examples above could not see that, because they put the worker in the
  # investigation's own account.
  describe "which worker may conclude which investigation" do
    let(:tenant) { create(:account) }
    let(:tenant_component) do
      create(:platform_component_status, account: tenant, component_kind: "docker_host",
                                         component_ref: "tenant-host",
                                         conditions: [ { "type" => "Connected", "status" => false,
                                                         "reason" => "ConnectionError", "severity" => "down" } ])
    end
    # Opened by a person in the tenant, the way the drawer opens one. Ranking
    # spends only as the opener (G1), so this is the user the ledger row names.
    let(:tenant_operator) { create(:user, account: tenant) }
    let(:tenant_investigation) do
      Platform::InvestigationService.new(account: tenant)
                                    .open!(tenant_component, trigger: "operator",
                                                             opened_by: tenant_operator)[:investigation]
    end

    it "lets the SYSTEM worker conclude another tenant's investigation" do
      stub_ranker('{"hypotheses":[]}')

      post_conclude(tenant_investigation.id)

      expect(response).to have_http_status(:ok)
      expect(tenant_investigation.reload).to be_concluded
    end

    # THE CLONE AND THE LEDGER ARE THE TENANT'S (A6 re-verification G3).
    #
    # Reaching another tenant's investigation is only half of it. The door
    # used to pass the WORKER's account to the ranker, so the clone that read
    # the tenant's evidence was minted in the worker's account and the spend
    # was booked there. This runs the REAL resolver — `agent_for` is not
    # stubbed — so the account the clone lands in is the account the code
    # actually chose.
    it "ranks as a clone in the TENANT's account and books the spend there" do
      canonical = create(:ai_agent, :global, name: "Infrastructure Generalist")
      stub_provider('{"hypotheses":[{"cause":"daemon died","evidence_classes":["conditions"],"score":1.0}]}')

      post_conclude(tenant_investigation.id)

      expect(response).to have_http_status(:ok)
      concluded = tenant_investigation.reload
      expect(concluded).to be_concluded
      expect(concluded.agent.account_id).to eq(tenant.id)
      expect(concluded.agent.id).not_to eq(canonical.id)

      execution = Ai::AgentExecution.where(ai_agent_id: concluded.agent_id).sole
      expect(execution.account_id).to eq(tenant.id)
      expect(execution.user_id).to eq(tenant_operator.id)
      # And nothing was minted in the worker's account.
      expect(Ai::Agent.where(account_id: account.id, cloned_from_id: canonical.id)).to be_empty
    end

    # The shared arm, THROUGH the door. An automatic trigger on a shared
    # component opens with no account, so no principal is minted anywhere — not
    # in the worker's account — and it concludes on core's own candidates.
    it "resolves no agent for a shared investigation through the door" do
      canonical = create(:ai_agent, :global, name: "Infrastructure Generalist")
      shared_component = create(:platform_component_status, :shared,
                                component_kind: "provider_circuit_breaker", component_ref: "breaker-g3",
                                verdict: Platform::ComponentStatus::DEGRADED,
                                conditions: [ { "type" => "Closed", "status" => false,
                                                "reason" => "BreakerOpen", "severity" => "degraded" } ])
      shared = Platform::InvestigationService.new(account: nil)
                                             .open!(shared_component, trigger: "down")[:investigation]
      stub_provider('{"hypotheses":[]}')

      post_conclude(shared.id)

      expect(response).to have_http_status(:ok)
      expect(shared.reload).to be_concluded
      expect(shared.reload.agent_id).to be_nil
      expect(Ai::Agent.where(cloned_from_id: canonical.id)).to be_empty
      expect(shared.reload.ranking_record)
        .to include("state" => "not_run", "reason" => "NoPrincipal", "retryable" => false)
    end

    # The other arm: an ACCOUNT worker stays anchored to its own tenant, and a
    # foreign id is NOT FOUND rather than forbidden.
    it "404s an ACCOUNT worker reaching another tenant's investigation" do
      account_worker = create(:worker, account: account, is_system: false)
      headers = { "X-Forwarded-Tls-Client-Cert-Info" =>
                    CGI.escape(%(Subject="CN=#{account_worker.node_instance_id}")) }

      post_conclude(tenant_investigation.id, headers: headers)

      expect(response).to have_http_status(:not_found)
      expect(tenant_investigation.reload).to be_open
    end
  end

  describe "the happy path" do
    it "stores hypotheses whose confidence core computed, not the ranker's" do
      agent = stub_ranker(<<~JSON)
        {"hypotheses":[
          {"cause":"upstream node lost","evidence_classes":["conditions","status_events"],"score":6.0,"confidence":0.99},
          {"cause":"credential expired","evidence_classes":["conditions"],"score":4.0}
        ]}
      JSON

      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      expect(body["data"]["ranked"]).to be(true)

      concluded = investigation.reload
      expect(concluded).to be_concluded
      expect(concluded.agent_id).to eq(agent.id)
      expect(concluded.top_hypothesis["cause"]).to eq("upstream node lost")
      # NOT the 0.99 the ranker volunteered.
      expect(concluded.top_hypothesis["confidence"]).to eq(0.45)
      expect(concluded.top_hypothesis["confidence_state"])
        .to eq(Platform::Investigation::Confidence::MEASURED)
    end

    it "tolerates a fenced JSON reply, which is what models actually send" do
      stub_ranker("Here you go:\n```json\n{\"hypotheses\":[{\"cause\":\"disk full\",\"evidence_classes\":[\"conditions\"],\"score\":1.0}]}\n```")

      post_conclude(investigation.id)

      expect(investigation.reload.top_hypothesis["cause"]).to eq("disk full")
    end

    # A ranker that read the evidence and found nothing has ANSWERED. That
    # concludes the investigation; it does not retry forever.
    it "concludes with no hypotheses when the ranker found none" do
      stub_ranker('{"hypotheses":[]}')

      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      expect(investigation.reload).to be_concluded
      expect(investigation.reload.hypotheses).to eq([])
    end

    # No canonical agent is core mode, not a fault: nothing will change on a
    # retry, so the investigation concludes on the deterministic candidates
    # core derived itself. A worse answer, not no answer.
    it "concludes deterministically when no agent resolves" do
      allow(Platform::Investigation::Ranking).to receive(:agent_for).and_return(nil)

      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      expect(investigation.reload).to be_concluded
      expect(investigation.reload.top_hypothesis["cause"]).to include("ConnectionError")
      expect(investigation.reload.agent_id).to be_nil
      expect(investigation.reload.ranking_record)
        .to include("state" => "not_run", "reason" => "NoPrincipal", "retryable" => false)
      expect(body.dig("data", "ranked")).to be(false)
    end

    # A retry after a timeout that actually succeeded must not spend a second
    # LLM call.
    it "is idempotent — a second call does not re-rank" do
      stub_ranker('{"hypotheses":[{"cause":"first answer","evidence_classes":["conditions"],"score":1.0}]}')
      post_conclude(investigation.id)

      stub_ranker('{"hypotheses":[{"cause":"second answer","evidence_classes":["conditions"],"score":1.0}]}')
      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      expect(body["data"]["reason"]).to eq("already_concluded")
      expect(investigation.reload.top_hypothesis["cause"]).to eq("first answer")
    end
  end

  # THE CROSS-APP CONTRACT. `PlatformInvestigationJob` lives in the worker and
  # reads `response["success"]`, `data.investigation.status` and
  # `data.investigation.hypotheses` off this response. The worker's spec can
  # only stub a shape; this is the arm that proves the shape is real, so a
  # rename here fails HERE rather than silently in production.
  describe "the response shape the worker job reads" do
    it "carries success and the keys the job names" do
      stub_ranker('{"hypotheses":[{"cause":"disk full","evidence_classes":["conditions"],"score":1.0}]}')

      post_conclude(investigation.id)

      expect(body["success"]).to be(true)
      expect(body.dig("data", "investigation", "status")).to eq("completed")
      expect(body.dig("data", "investigation", "hypotheses")).to be_an(Array)
    end

    it "carries success false when ranking fails, which is what makes the job raise" do
      stub_ranker("nonsense")

      post_conclude(investigation.id)

      expect(body["success"]).to be(false)
    end
  end

  describe "a ranker that answers unusably" do
    # Something IS wrong and may succeed on a retry, so the investigation stays
    # OPEN. Concluding here would burn the one open investigation this
    # component is allowed on a result we know is empty.
    it "leaves the investigation open and records the reason" do
      stub_ranker("I'm sorry, I can't help with that.")

      post_conclude(investigation.id)

      expect(response).to have_http_status(:unprocessable_content)
      reloaded = investigation.reload
      expect(reloaded).to be_open
      expect(reloaded.hypotheses).to eq([])
      expect(reloaded.ranking_record).to include("state" => "failed", "reason" => "RankerUnusable",
                                                 "retryable" => true, "attempts" => 1)
    end

    it "does the same when the provider call itself raises" do
      create(:ai_agent, account: account).tap do |agent|
        allow(Platform::Investigation::Ranking).to receive(:agent_for).and_return(agent)
      end
      allow(Ai::McpAgentExecutor).to receive(:new).and_raise(StandardError, "provider is down")

      post_conclude(investigation.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(investigation.reload).to be_open
      expect(investigation.reload.ranking_record["message"]).to include("provider is down")
      expect(investigation.reload.ranking_record["reason"]).to eq("ProviderError")
    end

    # The evidence that was already assembled must survive the error write —
    # recording the failure must not destroy the reason the investigation
    # exists.
    it "keeps the assembled evidence alongside the recorded error" do
      stub_ranker("nonsense")

      post_conclude(investigation.id)

      expect(investigation.reload.evidence["conditions"]).to be_present
    end
  end

  # A6 review F4 — a refusal a retry cannot change CONCLUDES, on core's own
  # candidates, with the reason recorded. Only a retryable failure stays open,
  # because the open-fingerprint index releases only when a row leaves `open`.
  describe "which failures end an investigation (F4)" do
    let(:max) { Platform::Investigation::Ranking::MAX_RANKING_ATTEMPTS }

    # Through the REAL security gate and the REAL principal resolution. Only
    # the provider boundary and the input guardrail are stubbed.
    it "concludes an AUTOMATIC investigation the gate refused, and says why" do
      create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
      create(:ai_provider, account: account)
      provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do
        provider_calls += 1
        { "output" => '{"hypotheses":[]}', "metadata" => {} }
      end
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails).and_return(blocked: false)
      automatic = Platform::InvestigationService.new(account: account)
                                                .open!(component, trigger: "down")[:investigation]

      post_conclude(automatic.id)

      expect(response).to have_http_status(:ok)
      reloaded = automatic.reload
      expect(reloaded).to be_concluded
      expect(reloaded.top_hypothesis["cause"]).to include("ConnectionError")
      expect(reloaded.agent_id).to be_nil
      expect(reloaded.ranking_record).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                                 "retryable" => false)
      expect(reloaded.conclusion).to include("automatic spend needs an agent-scoped grant")
      expect(body.dig("data", "ranked")).to be(false)
      expect(provider_calls).to eq(0)
      expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
      expect(Platform::InvestigationService.new(account: account)
               .open!(component, trigger: "down")[:opened]).to be(true)
    end

    # A6 re-review: refused before the gate at every tier, so the highest
    # tier is refused through the door too.
    it "refuses automatic spend at the highest tier, through the door" do
      canonical = create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
      create(:ai_agent_trust_score, :autonomous, account: account, agent: canonical)
      create(:ai_provider, account: account)
      provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
        provider_calls += 1
        { "output" => '{"hypotheses":[]}', "metadata" => {} }
      end
      automatic = Platform::InvestigationService.new(account: account)
                                                .open!(component, trigger: "down")[:investigation]

      post_conclude(automatic.id)

      expect(response).to have_http_status(:ok)
      expect(automatic.reload).to be_concluded
      expect(automatic.ranking_record).to include("reason" => "AutomaticSpendNeedsGrant", "retryable" => false)
      expect(provider_calls).to eq(0)
      expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
    end

    it "concludes on a gate refusal of an operator-opened investigation too" do
      stub_ranker('{"hypotheses":[]}')
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_pre_execution_security_gate).and_call_original
      allow_any_instance_of(Ai::Security::SecurityGateService).to receive(:pre_execution_gate)
        .and_return(allowed: false, blocked_by: :prompt_injection,
                    checks: [ { name: :prompt_injection, passed: false, blocked: true,
                                details: { reason: "Prompt injection detected" } } ])

      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      reloaded = investigation.reload
      expect(reloaded).to be_concluded
      expect(reloaded.ranking_record).to include("state" => "refused", "reason" => "SecurityGateRefused",
                                                 "retryable" => false)
      expect(reloaded.conclusion).to include("Ranking was refused")
    end

    it "concludes once the ranker has answered prose on every attempt the job makes" do
      stub_ranker("I'm sorry, I can't help with that.")

      statuses = Array.new(max) do
        post_conclude(investigation.id)
        response.status
      end

      expect(statuses).to eq([ 422 ] * (max - 1) + [ 200 ])
      reloaded = investigation.reload
      expect(reloaded).to be_concluded
      expect(reloaded.agent_id).to be_nil
      expect(reloaded.ranking_record).to include("state" => "failed", "reason" => "RankerUnusable",
                                                 "retryable" => false, "attempts" => max)
    end

    # G2-2: a provider failure stays open while the job will retry it, and
    # concludes on the job's last attempt, after which nothing retries.
    it "keeps a provider failure open while the job retries, and concludes on its last attempt" do
      create(:ai_agent, account: account).tap do |agent|
        allow(Platform::Investigation::Ranking).to receive(:agent_for).and_return(agent)
      end
      allow(Ai::McpAgentExecutor).to receive(:new).and_raise(StandardError, "provider is down")

      statuses = Array.new(max) do
        post_conclude(investigation.id)
        response.status
      end

      expect(statuses).to eq([ 422 ] * (max - 1) + [ 200 ])
      reloaded = investigation.reload
      expect(reloaded).to be_concluded
      expect(reloaded.top_hypothesis["cause"]).to include("ConnectionError")
      expect(reloaded.ranking_record).to include("state" => "failed", "reason" => "ProviderError",
                                                 "retryable" => false, "attempts" => max)
      expect(reloaded.conclusion).to include("the provider failed on all #{max} attempts")
      expect(Platform::InvestigationService.new(account: account)
               .open!(component, trigger: "operator")[:opened]).to be(true)
    end

    it "clears the recorded failure when a later attempt ranks" do
      stub_ranker("nonsense")
      post_conclude(investigation.id)

      stub_ranker('{"hypotheses":[{"cause":"disk full","evidence_classes":["conditions"],"score":1.0}]}')
      post_conclude(investigation.id)

      expect(response).to have_http_status(:ok)
      expect(investigation.reload.ranking_record).to be_nil
      expect(investigation.reload.top_hypothesis["cause"]).to eq("disk full")
    end
  end

  # The bounds live in the service, so they hold through THIS door too, not
  # only through the MCP verb.
  describe "the bounds hold end to end through the internal door" do
    it "keeps the open-fingerprint rule intact until the investigation concludes" do
      investigation
      service = Platform::InvestigationService.new(account: account)

      expect(service.open!(component, trigger: "down"))
        .to eq(refused: Platform::InvestigationService::REFUSED_ALREADY_OPEN)

      stub_ranker('{"hypotheses":[]}')
      post_conclude(investigation.id)

      # And releases it once concluded — the reason the index is partial.
      expect(service.open!(component, trigger: "down")[:opened]).to be(true)
    end

    it "still counts a concluded investigation against the daily cap" do
      investigation
      stub_ranker('{"hypotheses":[]}')
      post_conclude(investigation.id)

      allow(Platform::InvestigationService).to receive(:daily_cap).and_return(1)

      expect(Platform::InvestigationService.new(account: account).open!(component, trigger: "down"))
        .to eq(refused: Platform::InvestigationService::REFUSED_DAILY_CAP)
    end
  end
end
