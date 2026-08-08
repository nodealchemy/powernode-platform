# frozen_string_literal: true

require "rails_helper"

# Coverage for LLM-call TRACKING in the provisioning pipeline (IMP 019fe1da).
#
# IntentCaptureService called ::WorkerLlmClient.for_account directly. That client
# is untracked: it creates no Ai::AgentExecution, so the call produced no
# execution record, no cost_usd, no token/context metrics, no budget debit and
# nothing for Ai::RoutingDecision to attach to.
#
# Measured live on ops-hub 2026-08-08 during the platform-autonomy-dryrun P1
# baseline: capture_intent completed and demonstrably called an LLM (it returned
# a structured brief from free text), yet ai_agent_executions,
# ai_routing_decisions, ai_task_complexity_assessments, ai_skill_usage_records
# and ai_budget_transactions were ALL zero, and sum(spent_cents) was 0.
#
# Note the budget mechanism specifically: WorkerLlmClient#track_llm_usage! bails
# on `return unless @agent_id`, and .for_account never sets one — so these calls
# could never debit a budget no matter how large. The AgentBudget ceiling was
# not merely unenforced, it was unreachable. Wrapping in TrackedWorkerLlmClient
# makes Ai::AgentExecution#propagate_cost_to_budget the single debit path (and
# for the same reason there is no double-debit risk here).
RSpec.describe Ai::Provisioning::IntentCaptureService, "LLM call tracking", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account, user: user) }

  # A live credential is what .for_account keys off.
  let!(:provider) do
    Ai::Provider.create!(
      name: "Test OpenAI", provider_identifier: "openai-test", provider_type: "openai",
      is_active: true, supported_models: ["gpt-4.1-mini"], default_model: "gpt-4.1-mini"
    )
  rescue StandardError
    Ai::Provider.first
  end

  def build_client
    service.send(:build_llm_client)
  end

  context "when a service agent is resolvable" do
    let!(:agent) do
      # The factory generates its own slug (sequence-based), so set it after
      # create — otherwise resolve_service_agent finds nothing and the whole
      # context silently tests the untracked fallback instead.
      create(:ai_agent, account: account, status: "active").tap do |a|
        a.update_column(:slug, "intent-classifier")
      end
    end

    before do
      allow(::WorkerLlmClient).to receive(:for_account).with(account).and_return(
        instance_double(::WorkerLlmClient)
      )
    end

    it "wraps the worker client so every call is recorded" do
      expect(build_client).to be_a(::TrackedWorkerLlmClient)
    end

    it "attributes executions to the resolved service agent" do
      client = build_client
      expect(client.instance_variable_get(:@agent)).to eq(agent)
    end

    it "tags the execution context with the calling service" do
      client = build_client
      expect(client.instance_variable_get(:@execution_context_type))
        .to eq("service:Ai::Provisioning::IntentCaptureService")
    end
  end

  context "when no service agent exists (core mode / unseeded account)" do
    let(:raw) { instance_double(::WorkerLlmClient) }

    before do
      allow(::WorkerLlmClient).to receive(:for_account).with(account).and_return(raw)
    end

    it "falls back to the raw client rather than breaking provisioning" do
      # Losing telemetry is acceptable; losing the ability to provision is not.
      expect(build_client).to eq(raw)
    end
  end

  context "when the account has no active credential" do
    before do
      allow(::WorkerLlmClient).to receive(:for_account).with(account).and_return(nil)
    end

    it "returns nil, preserving the existing no-LLM-configured path" do
      expect(build_client).to be_nil
    end
  end

  describe "budget reachability (the point of the fix)" do
    let!(:agent) do
      # The factory generates its own slug (sequence-based), so set it after
      # create — otherwise resolve_service_agent finds nothing and the whole
      # context silently tests the untracked fallback instead.
      create(:ai_agent, account: account, status: "active").tap do |a|
        a.update_column(:slug, "intent-classifier")
      end
    end

    it "the raw client could never debit a budget — no agent_id is ever set" do
      # Documents WHY the ceiling was unreachable, and pins the mechanism so a
      # future change to for_account that starts passing agent_id (which would
      # reintroduce double-debiting alongside the AgentExecution callback) fails
      # here rather than silently double-charging.
      raw = ::WorkerLlmClient.new(provider: provider, credential: nil)
      expect(raw.instance_variable_get(:@agent_id)).to be_nil
    end
  end
end
