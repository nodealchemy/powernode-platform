# frozen_string_literal: true

require "rails_helper"

# Component status plane, A6 review fixes — hypothesis ranking, driven through
# the REAL `Ai::McpAgentExecutor` with only the provider boundary stubbed.
#
# THE EXECUTOR IS NEVER DOUBLED HERE, and that is the point of the file. The
# original A6 specs replaced it with an `instance_double` returning a shape it
# never returns, so every real ranking failed while every example stayed green.
# `instance_double` verifies the SIGNATURE of `execute`, never the shape of
# what it returns, so a total double of a collaborator cannot catch a contract
# mismatch with that collaborator.
RSpec.describe Platform::Investigation::Ranking do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) }

  let(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: Platform::ComponentStatus::DOWN,
                                       conditions: [ { "type" => "Connected", "status" => false,
                                                       "reason" => "ConnectionError",
                                                       "severity" => "down" } ])
  end

  let(:investigation) do
    # Opened BY A PERSON, the way the REST and MCP doors open one. Ranking
    # spends only as the opener (G1), so an investigation with no opener gets
    # no ledger row; the automatic arm is proved separately against the real
    # gate below.
    Platform::InvestigationService.new(account: account)
                                  .open!(component, trigger: "operator", opened_by: owner)[:investigation]
  end

  let(:valid_json) do
    '{"hypotheses":[{"cause":"docker daemon died","evidence_classes":["conditions","status_events"],' \
      '"score":6.0},{"cause":"network partition","evidence_classes":["conditions"],"score":4.0}]}'
  end

  before { allow(WorkerJobService).to receive(:enqueue_job) }

  # Only the LLM call and the gates. `format_mcp_response` — the method that
  # nests the provider's text under "result" — runs for real.
  def stub_provider(output)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
      .and_return("output" => output, "metadata" => { "tokens_used" => 10 })
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_pre_execution_security_gate).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails).and_return(blocked: false)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_post_execution_security_gate).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_output_guardrails).and_return(blocked: false)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:validate_output!).and_return(true)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:write_back_to_memory).and_return(nil)
    allow_any_instance_of(Ai::McpAgentExecutor).to receive(:record_security_telemetry).and_return(nil)
  end

  describe "the executor's real return shape (F1)" do
    it "reads the provider text the executor actually returns" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider(valid_json)

      result = described_class.run!(investigation, account: account)

      expect(result[:error]).to be_nil
      expect(result[:ranked].map { |c| c[:cause] }).to eq([ "docker daemon died", "network partition" ])
    end

    # The shape itself, asserted directly, so the rule above is anchored to
    # something a reader can check rather than to a passing parse.
    it "finds the text nested under 'result', where format_mcp_response puts it" do
      agent = create(:ai_agent, account: account)
      stub_provider(valid_json)

      raw = Ai::McpAgentExecutor.new(agent: agent, account: account).execute("input" => "hi")

      expect(raw.dig("result", "output")).to eq(valid_json)
      # The three keys the code used to read. All nil — which is why every
      # ranking reported "no output" and every investigation stayed open.
      expect(raw["output"]).to be_nil
      expect(raw[:output]).to be_nil
      expect(raw[:response]).to be_nil
    end

    # A BLOCK IS NOT AN EMPTY ANSWER. The executor returns {"error" => {...}}
    # rather than raising when a gate refuses, and reporting that as "no
    # output" would send an operator to the provider for a refusal the
    # platform itself issued.
    #
    # And a refusal ENDS ranking (F4): the same input would meet the same gate
    # on a retry, so it comes back terminal, not as a retryable error.
    it "reports a security-gate block in the gate's own words, as a refusal" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider(valid_json)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_pre_execution_security_gate)
        .and_return("error" => { "type" => "SecurityGateViolation", "blocked_by" => "prompt_injection",
                                 "message" => "Blocked by security gate (prompt_injection): nope" })

      outcome = described_class.run!(investigation, account: account)

      expect(outcome[:error]).to be_nil
      expect(outcome[:ranked]).to be_nil
      expect(outcome[:ranking]).to include("state" => "refused", "reason" => "SecurityGateRefused",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("Blocked by security gate (prompt_injection): nope")
    end

    # The executor's OTHER refusal type. A guardrail block is the same kind of
    # decision about the same input, so it ends ranking the same way.
    it "treats a guardrail block as a refusal too" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider(valid_json)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails)
        .and_return(blocked: true, violations: [ { message: "topic not allowed" } ])

      outcome = described_class.run!(investigation, account: account)

      expect(outcome[:ranking]).to include("state" => "refused", "reason" => "SecurityGateRefused",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("Blocked by input guardrail: topic not allowed")
    end

    # The other arm: a provider failure the executor CAUGHT comes back as an
    # error hash too, and it is retryable, not a refusal.
    it "reports a provider failure the executor caught as retryable" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider(valid_json)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_raise(StandardError, "provider is down")

      outcome = described_class.run!(investigation, account: account)

      expect(outcome).to include(error: "provider is down", reason: described_class::REASON_PROVIDER_ERROR)
      expect(outcome).not_to have_key(:ranking)
    end

    it "still reports no output when the provider genuinely returns none" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider("")

      outcome = described_class.run!(investigation, account: account)

      expect(outcome[:error]).to eq("ranker returned no output")
      expect(outcome[:reason]).to eq(described_class::REASON_RANKER_UNUSABLE)
    end

    it "reports unusable prose as unusable, not as a conclusion" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider("I'm sorry, I can't help with that.")

      outcome = described_class.run!(investigation, account: account)

      expect(outcome[:error]).to eq("ranker returned no usable hypotheses")
      expect(outcome[:reason]).to eq(described_class::REASON_RANKER_UNUSABLE)
    end
  end

  # A6 re-verification G1, arms 2 and 3, through the REAL pre-execution
  # security gate and the REAL principal resolution: a global canonical, minted
  # into a clone in this account. Only the provider boundary and the NON-gate
  # rails are stubbed. Arm 1, automatic spend WITH an agent-scoped grant,
  # waits on A6b.
  describe "the real security gate decides who may spend (G1)" do
    let!(:canonical) do
      create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
    end
    let!(:account_provider) { create(:ai_provider, account: account) }

    def stub_non_gate_rails
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails).and_return(blocked: false)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_post_execution_security_gate).and_return(nil)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_output_guardrails).and_return(blocked: false)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:validate_output!).and_return(true)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:write_back_to_memory).and_return(nil)
    end

    it "refuses an AUTOMATIC investigation's spend, records why, and books nothing" do
      stub_non_gate_rails
      provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do
        provider_calls += 1
        { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
      end
      automatic = Platform::InvestigationService.new(account: account)
                                                .open!(component, trigger: "down")[:investigation]
      expect(automatic.opened_by_user_id).to be_nil

      outcome = described_class.run!(automatic, account: account)

      expect(outcome[:ranked]).to be_nil
      expect(outcome[:agent]).to be_nil
      expect(outcome[:ranking]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("automatic spend needs an agent-scoped grant")
      expect(provider_calls).to eq(0)
      expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
    end

    # A6 re-review: the gate alone was not enough. At the seeded monitored
    # tier the capability matrix ALLOWS execute, and the automatic call went
    # out with no ledger row. Automatic spend is now refused before the gate,
    # whatever the matrix answers, up to the highest tier.
    %i[monitored autonomous].each do |tier|
      it "refuses automatic spend at the #{tier} tier, where the matrix itself would allow it" do
        stub_non_gate_rails
        create(:ai_agent_trust_score, tier, account: account, agent: canonical)
        expect(Ai::Autonomy::CapabilityMatrixService.new(account: account)
                 .check(agent: canonical, action_type: "execute")).to eq(:allowed)
        provider_calls = 0
        allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
          provider_calls += 1
          { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
        end
        automatic = Platform::InvestigationService.new(account: account)
                                                  .open!(component, trigger: "down")[:investigation]

        outcome = described_class.run!(automatic, account: account)

        expect(outcome[:ranking]).to include("reason" => "AutomaticSpendNeedsGrant", "retryable" => false)
        expect(provider_calls).to eq(0)
        expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
        expect(Ai::Agent.where(cloned_from_id: canonical.id)).to be_empty
      end
    end

    it "lets an OPERATOR-opened investigation spend, as that operator — the other arm" do
      stub_non_gate_rails
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_return("output" => valid_json, "metadata" => { "tokens_used" => 10 })
      operator = create(:user, account: account)
      opened = Platform::InvestigationService.new(account: account)
                                             .open!(component, trigger: "operator", opened_by: operator)[:investigation]

      outcome = described_class.run!(opened, account: account)

      expect(outcome[:ranking]).to be_nil
      expect(outcome[:error]).to be_nil
      expect(outcome[:ranked].map { |c| c[:cause] }).to include("docker daemon died")
      execution = Ai::AgentExecution.where(account_id: account.id).sole
      expect(execution.user_id).to eq(operator.id)
      expect(execution.ai_agent_id).to eq(outcome[:agent].id)
    end

    # A6 H1: an AGENT-opened investigation is automatic. The tool bridge and an
    # MCP client session both hand the verb a user beside the agent (its
    # creator, or the session's owner). That user is the authority the call was
    # checked against, never a person's consent to spend.
    it "refuses an AGENT-opened investigation's spend with its creator beside it, and books nothing" do
      stub_non_gate_rails
      provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
        provider_calls += 1
        { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
      end
      creator = create(:user, account: account)
      asking_agent = create(:ai_agent, account: account, creator: creator)
      opened = Platform::InvestigationService.new(account: account)
                                             .open!(component, trigger: "operator", opened_by: creator,
                                                               via_mcp: true, opened_by_agent: asking_agent)[:investigation]
      expect(opened.opened_by_user_id).to be_nil
      expect(opened.opened_by_agent_id).to eq(asking_agent.id)

      outcome = described_class.run!(opened, account: account)

      expect(outcome[:ranking]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("An agent opened this investigation")
      expect(provider_calls).to eq(0)
      expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
      expect(Ai::Agent.where(cloned_from_id: canonical.id)).to be_empty
    end

    # A6 H1, keyed on the TRANSPORT: an MCP call with no client agent behind it
    # is no more a person's consent than one with an agent. The message names
    # the MCP client and says where a ranked diagnosis can come from.
    it "refuses an investigation opened over MCP with no agent behind it, naming the MCP client" do
      stub_non_gate_rails
      provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
        provider_calls += 1
        { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
      end
      token_owner = create(:user, account: account)
      opened = Platform::InvestigationService.new(account: account)
                                             .open!(component, trigger: "operator", opened_by: token_owner,
                                                               via_mcp: true)[:investigation]
      expect(opened.opened_by_user_id).to be_nil
      expect(opened.opened_by_agent_id).to be_nil

      outcome = described_class.run!(opened, account: account)

      expect(outcome[:ranking]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("An MCP client opened this investigation")
      expect(outcome[:ranking]["message"]).to include("open an investigation from the status page")
      expect(provider_calls).to eq(0)
      expect(Ai::AgentExecution.where(account_id: account.id).count).to eq(0)
      expect(Ai::Agent.where(cloned_from_id: canonical.id)).to be_empty
    end
  end

  # A6 re-review: NO PROVIDER CALL WITHOUT A LEDGER ROW, on every path
  # through ranking. Each provider call records whether the executor held a
  # persisted execution row at that moment.
  describe "the ledger invariant" do
    def component_named(ref)
      create(:platform_component_status, account: account, component_kind: "docker_host", component_ref: ref,
                                         verdict: Platform::ComponentStatus::DOWN,
                                         conditions: [ { "type" => "Connected", "status" => false,
                                                         "reason" => "ConnectionError", "severity" => "down" } ])
    end

    it "never lets a provider call go out without a persisted ledger row" do
      stub_provider(valid_json)
      rows_at_call = []
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |executor, *_args|
        row = executor.instance_variable_get(:@execution)
        rows_at_call << (row.is_a?(Ai::AgentExecution) && row.persisted?)
        { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
      end
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      service = Platform::InvestigationService.new(account: account)
      automatic = service.open!(component_named("host-2"), trigger: "down")[:investigation]
      ledger_down = service.open!(component_named("host-3"), trigger: "operator", opened_by: owner)[:investigation]

      described_class.run!(investigation, account: account)
      described_class.run!(automatic, account: account)
      allow(Ai::AgentExecution).to receive(:create!).and_raise(StandardError, "ledger is down")
      described_class.run!(ledger_down, account: account)

      expect(rows_at_call).to eq([ true ])
    end
  end

  # A6 review F4 — what stays open. Only `record_outcome!` decides it.
  describe ".record_outcome!" do
    let(:unusable) { { error: "ranker returned no usable hypotheses", reason: described_class::REASON_RANKER_UNUSABLE } }

    it "counts unusable answers and turns terminal on the last one the job will make" do
      records = Array.new(described_class::MAX_RANKING_ATTEMPTS) do
        described_class.record_outcome!(investigation, unusable)
      end

      expect(records.map { |r| r["attempts"] }).to eq((1..described_class::MAX_RANKING_ATTEMPTS).to_a)
      expect(records.map { |r| r["retryable"] })
        .to eq([ true ] * (described_class::MAX_RANKING_ATTEMPTS - 1) + [ false ])
      expect(records.last).to include("state" => "failed", "reason" => "RankerUnusable")
      expect(investigation.reload.ranking_record).to eq(records.last)
    end

    # G2-2: the job's last attempt is the last for a provider failure too.
    # After it nothing retries, so a retryable record would promise a retry
    # that never comes while the open row refuses every new investigation.
    it "exhausts a provider failure on the job's last attempt too" do
      provider_down = { error: "StandardError: provider is down", reason: described_class::REASON_PROVIDER_ERROR }

      records = Array.new(described_class::MAX_RANKING_ATTEMPTS) do
        described_class.record_outcome!(investigation, provider_down)
      end

      expect(records.map { |r| r["retryable"] })
        .to eq([ true ] * (described_class::MAX_RANKING_ATTEMPTS - 1) + [ false ])
      expect(records.last).to include("state" => "failed", "reason" => "ProviderError")
      expect(records.last["message"]).to include("provider is down")
    end

    it "clears the record when an agent finally ranks it" do
      described_class.record_outcome!(investigation, unusable)

      expect(described_class.record_outcome!(investigation, { ranked: [], agent: owner })).to be_nil
      expect(investigation.reload.evidence).not_to have_key("ranking")
    end
  end

  describe "#agent_for — the acting principal (F3)" do
    let!(:canonical) do
      create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
    end

    # A GLOBAL canonical is a TEMPLATE, not a principal. Ai::Tools::BaseTool
    # refuses one by name, and the executor does not — so ranking with one
    # would run against a principal with no account and no account role
    # bounding it.
    it "does not hand back the global canonical" do
      acting = described_class.agent_for(investigation, account)

      expect(acting).not_to be_nil
      expect(acting.account_id).to eq(account.id)
      expect(acting.account_id).not_to be_nil
      expect(acting.id).not_to eq(canonical.id)
    end

    it "resolves through the one HIER-P2I resolver rather than a second copy" do
      expect(Ai::Agents::AccountPrincipalResolver)
        .to receive(:acting).with(instance_of(Ai::Agent), account: account).and_call_original

      described_class.agent_for(investigation, account)
    end

    it "passes an account-scoped agent through untouched — the other arm" do
      own = create(:ai_agent, account: account, name: "Infrastructure Generalist")

      expect(described_class.agent_for(investigation, account).id).to eq(own.id)
    end

    # A shared component has no tenant, so there is no account principal to
    # mint and none is invented. Falling back to the canonical here would be
    # the exact bypass this method exists to close.
    it "resolves nothing for a shared investigation, rather than the canonical" do
      shared_component = create(:platform_component_status, :shared,
                                component_kind: "provider_circuit_breaker", component_ref: "breaker-1")
      shared = Platform::InvestigationService.new(account: nil)
                                             .open!(shared_component, trigger: "operator")[:investigation]

      expect(described_class.agent_for(shared, nil)).to be_nil
    end
  end

  describe "the LLM spend (F7)" do
    before do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider(valid_json)
    end

    it "records an Ai::AgentExecution for the call" do
      expect { described_class.run!(investigation, account: account) }
        .to change { Ai::AgentExecution.where(account_id: account.id).count }.by(1)

      execution = Ai::AgentExecution.where(account_id: account.id).last
      expect(execution.status).to eq("completed")
      expect(execution.input_parameters["investigation_id"]).to eq(investigation.id)
      expect(execution.input_parameters["invocation_type"]).to eq("platform_investigation")
    end

    it "hands that execution to the executor, so telemetry books against it" do
      expect(Ai::McpAgentExecutor).to receive(:new)
        .with(hash_including(execution: instance_of(Ai::AgentExecution))).and_call_original

      described_class.run!(investigation, account: account)
    end

    # The other arm: a failed call still closes its ledger row rather than
    # leaving a `pending` execution behind forever.
    it "marks the execution failed when the ranker produces nothing" do
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_return("output" => "", "metadata" => {})

      described_class.run!(investigation, account: account)

      expect(Ai::AgentExecution.where(account_id: account.id).last.status).to eq("failed")
      expect(investigation.reload.cost_usd).to be_nil
    end

    # F7, the arm the review found missing: a real token count reaches the
    # ledger and becomes a real, nonzero cost on both rows. The oracle is the
    # pricing service itself, not a copied number.
    it "books the provider's tokens and a priced, nonzero cost onto both rows" do
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_return("output" => valid_json,
                    "metadata" => { "tokens_used" => 5000, "prompt_tokens" => 4000,
                                    "completion_tokens" => 1000, "model_used" => "gpt-4o" })
      expected = Ai::CostCalculationService.calculate(model_id: "gpt-4o", prompt_tokens: 4000,
                                                      completion_tokens: 1000)

      described_class.run!(investigation, account: account)

      execution = Ai::AgentExecution.where(account_id: account.id).last
      expect(expected).to be > 0
      expect(execution.tokens_used).to eq(5000)
      expect(execution.cost_usd.to_f).to eq(expected)
      expect(investigation.reload.cost_usd.to_f).to eq(expected)
    end

    # The column default is 0.0; copying it made every investigation report
    # that it cost nothing, including the ones nobody measured.
    it "leaves the investigation's cost nil when the provider reported no usage" do
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_return("output" => valid_json, "metadata" => {})

      described_class.run!(investigation, account: account)

      expect(Ai::AgentExecution.where(account_id: account.id).last.status).to eq("completed")
      expect(investigation.reload.cost_usd).to be_nil
    end

    # NO LEDGER ROW, NO CALL (A6 re-review). A ledger that could not be
    # written used to let the call go ahead unrecorded. Now the provider is
    # never called, and the attempt is retryable like any transient failure.
    it "makes no provider call when the ledger row cannot be written" do
      allow(Ai::AgentExecution).to receive(:create!).and_raise(StandardError, "ledger is down")
      calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
        calls += 1
        { "output" => valid_json, "metadata" => {} }
      end

      outcome = described_class.run!(investigation, account: account)

      expect(calls).to eq(0)
      expect(outcome).to include(reason: described_class::REASON_LEDGER_UNAVAILABLE)
      expect(outcome[:error]).to include("ledger is down")
    end

    # The re-review found cost_usd kept only the LAST attempt. It accumulates.
    it "adds up the cost of every attempt, not just the last one" do
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider)
        .and_return("output" => "I'm sorry, I can't help with that.",
                    "metadata" => { "tokens_used" => 5000, "prompt_tokens" => 4000,
                                    "completion_tokens" => 1000, "model_used" => "gpt-4o" })
      per_attempt = Ai::CostCalculationService.calculate(model_id: "gpt-4o", prompt_tokens: 4000,
                                                         completion_tokens: 1000)

      3.times { described_class.run!(investigation, account: account) }

      expect(per_attempt).to be > 0
      expect(investigation.reload.cost_usd.to_f).to be_within(0.000001).of(per_attempt * 3)
      expect(Ai::AgentExecution.where(account_id: account.id).sum(:cost_usd).to_f)
        .to be_within(0.000001).of(per_attempt * 3)
    end
  end

  # THE COMPLETION ORACLE for the A6 review. It goes green only when F1, F2 and
  # F3 are all fixed: the enqueue has to happen, the principal has to resolve
  # to something that can act, and the executor's return shape has to be read
  # correctly. Any one of the three reverted turns this red.
  describe "end to end: open! → enqueue → conclude" do
    let!(:canonical) do
      create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
    end

    it "carries one component from opened to concluded with a core-computed confidence" do
      enqueued = []
      allow(WorkerJobService).to receive(:enqueue_job) { |name, opts| enqueued << [ name, opts ] }
      stub_provider(valid_json)

      # 1. A door opens it. Evidence recorded, nothing ranked yet.
      opened = Platform::InvestigationService.new(account: account)
                                             .open!(component, trigger: "operator", opened_by: owner)[:investigation]
      expect(opened).to be_open
      expect(opened.hypotheses).to eq([])

      # 2. The enqueue really happened, naming this row.
      expect(enqueued.size).to eq(1)
      expect(enqueued.first.first).to eq("PlatformInvestigationJob")
      expect(enqueued.first.last[:args].first["investigation_id"]).to eq(opened.id)

      # 3. What the worker's POST reaches: rank, then conclude.
      ranking = described_class.run!(opened, account: account)
      expect(ranking[:error]).to be_nil
      expect(ranking[:agent].account_id).to eq(account.id)

      concluded = Platform::InvestigationService.new(account: account)
                                                .conclude!(opened, ranked: ranking[:ranked],
                                                                   agent: ranking[:agent])

      # 4. Concluded, with the confidence CORE computed from two candidates
      #    across two evidence classes — 0.6 share × 0.75 class factor.
      expect(concluded).to be_concluded
      expect(concluded.top_hypothesis["cause"]).to eq("docker daemon died")
      expect(concluded.top_hypothesis["confidence"]).to eq(0.45)
      expect(concluded.agent_id).to eq(ranking[:agent].id)

      # 5. And the bound released: the component is investigable again, which
      #    it never was while every investigation stayed open forever.
      expect(Platform::InvestigationService.new(account: account)
               .open!(component, trigger: "down")[:opened]).to be(true)
    end
  end
end
