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
    Platform::InvestigationService.new(account: account).open!(component, trigger: "operator")[:investigation]
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
    it "reports a security-gate block in the gate's own words" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_pre_execution_security_gate)
        .and_return("error" => { "message" => "Blocked by security gate (anomaly_precheck): nope" })

      expect(described_class.run!(investigation, account: account)[:error])
        .to include("Blocked by security gate")
    end

    it "still reports no output when the provider genuinely returns none" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider("")

      expect(described_class.run!(investigation, account: account)[:error])
        .to eq("ranker returned no output")
    end

    it "reports unusable prose as unusable, not as a conclusion" do
      allow(described_class).to receive(:agent_for).and_return(create(:ai_agent, account: account))
      stub_provider("I'm sorry, I can't help with that.")

      expect(described_class.run!(investigation, account: account)[:error])
        .to eq("ranker returned no usable hypotheses")
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
    end

    # A ledger that cannot be written must not stop the diagnosis.
    it "still ranks when the execution record cannot be created" do
      allow(Ai::AgentExecution).to receive(:create!).and_raise(StandardError, "ledger is down")

      expect(described_class.run!(investigation, account: account)[:ranked]).to be_present
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
                                             .open!(component, trigger: "operator")[:investigation]
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
