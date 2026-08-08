# frozen_string_literal: true

require "rails_helper"

# Governed tier routing on the provisioning LLM seam — the fifth oracle.
#
# Ai::RoutingDecision and Ai::TaskComplexityAssessment are written by
# AgentBackedService#resolve_task_tier. The provisioning services never called
# it, so those two tables stayed empty even after their LLM calls started
# producing Ai::AgentExecution rows. Measured on ops-hub 2026-08-08: executions
# and cost populated, routing_decisions and complexity_assessments still 0.
#
# Two properties matter, and the second is the one worth guarding:
#
#   1. GATED. resolve_task_tier returns nil unless
#      TaskTierResolver.enabled_for?(account), so with the gate off the call is
#      byte-identical to before — same model, no resolver invocation at all.
#
#   2. APPLIED WHERE SAFE. A resolution that does not substitute (its model is
#      the baseline) drives the model/effort actually sent.
#
#      SUPERSEDED FRAMING, kept because the correction matters: this originally
#      read "applied, not merely recorded — recording a decision while calling
#      something else makes the oracle actively misleading". That posed a false
#      binary and cost a live run: the resolver downgraded intent capture to a
#      reasoning-tier model, which answered in prose, and the brief came back
#      empty. The third option is to record the decision AND record that it was
#      declined, with the reason — strictly more governance data than a silent
#      application, and no breakage. This seam's structured-output contract is
#      enforced in intent_capture_contract_spec.rb.
RSpec.describe Ai::Provisioning::IntentCaptureService, "tier routing", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account: account, user: user) }

  let!(:agent) do
    create(:ai_agent, account: account, creator: user, status: "active").tap do |a|
      a.update_column(:slug, "intent-classifier")
    end
  end

  let(:response) do
    instance_double("WorkerLlmResponse", success?: true, content: '{"intent":"x"}',
                                         prompt_tokens: 5, completion_tokens: 5, cached_tokens: 0,
                                         total_tokens: 10, model: "m", provider: "p")
  end
  let(:client) { instance_double(::TrackedWorkerLlmClient) }

  before { allow(service).to receive(:llm_client).and_return(client) }

  context "when the routing gate is OFF (default)" do
    before { allow(::Ai::Routing::TaskTierResolver).to receive(:enabled_for?).and_return(false) }

    it "never invokes the resolver" do
      expect(::Ai::Routing::TaskTierResolver).not_to receive(:resolve)
      allow(client).to receive(:complete).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "sends the pre-existing model, unchanged" do
      expect(client).to receive(:complete)
        .with(hash_including(model: service.send(:resolve_model))).and_return(response)
      service.capture(natural_language: "provision a node")
    end
  end

  context "when the routing gate is ON" do
    # baseline_model == model: the resolver did NOT substitute, so there is
    # nothing for the structured-output contract to be unsafe about and the
    # resolution applies. A SUBSTITUTING resolution is declined here — see
    # intent_capture_contract_spec.rb, which covers that path and the
    # considered-but-not-applied annotation.
    let(:resolution) do
      instance_double(::Ai::Routing::TaskTierResolver::Resolution,
                      model: "claude-opus-4-8", effort: "high", tier: :reasoning,
                      baseline_model: "claude-opus-4-8")
    end

    before do
      allow(::Ai::Routing::TaskTierResolver).to receive(:enabled_for?).and_return(true)
      allow(service).to receive(:resolve_task_tier).and_return(resolution)
      allow(service).to receive(:routing_decision_id).and_return("rd-123")
    end

    it "applies a non-substituting resolution's model" do
      expect(client).to receive(:complete)
        .with(hash_including(model: "claude-opus-4-8")).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "passes the resolved effort through" do
      expect(client).to receive(:complete)
        .with(hash_including(effort: "high")).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "links the routing decision to the execution the call creates" do
      expect(client).to receive(:complete)
        .with(hash_including(routing_decision_id: "rd-123")).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "resolves the tier against the tracking agent, tagged with a task_type" do
      allow(client).to receive(:complete).and_return(response)
      expect(service).to receive(:resolve_task_tier)
        .with(hash_including(task_type: "provisioning_intent_capture"))
        .and_return(resolution)
      service.capture(natural_language: "provision a node")
    end
  end

  context "when the resolver fails or returns nothing" do
    before do
      allow(::Ai::Routing::TaskTierResolver).to receive(:enabled_for?).and_return(true)
      allow(service).to receive(:resolve_task_tier).and_return(nil)
      allow(service).to receive(:routing_decision_id).and_return(nil)
    end

    it "falls back to the baseline model instead of breaking the call" do
      expect(client).to receive(:complete)
        .with(hash_including(model: service.send(:resolve_model))).and_return(response)
      service.capture(natural_language: "provision a node")
    end
  end
end
