# frozen_string_literal: true

require "rails_helper"

# Two guards added after a governed-router downgrade silently emptied a brief.
#
# What happened: resolve_task_tier scored intent-capture "moderate 0.338" and
# downgraded gpt-4o -> o3-mini. The call SUCCEEDED (2044 tokens) but returned
# content carrying no JSON object, so parse_brief_json fell through
# `return nil unless json.is_a?(Hash)` — the one path with NO log line — and the
# brief came back empty. Three layers later the operator saw
# "CompositionError: intent is required", which names neither the model
# substitution nor the parse miss.
#
# 1. OUTPUT CONTRACT. The existing seams that apply a tier resolution
#    (provider_execution.rb:92, task_executor.rb:492) drive free-form
#    conversations — any model produces usable output. IntentCaptureService
#    requires JSON conforming to BRIEF_SCHEMA, and the resolver knows nothing
#    about that. A caller must be able to declare the contract, and a
#    substitution that cannot be shown to satisfy it must not happen.
#
#    Critically the decision is still RECORDED, marked not-applied with a reason.
#    The earlier framing of this as "apply (risk breakage) vs record-only (data
#    that lies)" was a false binary: a decision recorded as considered-and-
#    declined is MORE complete governance data than one silently applied, not
#    less.
#
# 2. LOUD PARSE FAILURE. Whatever the router does, "the model returned something
#    unparseable" must never be silent.
RSpec.describe Ai::Provisioning::IntentCaptureService, "output contract + parse visibility", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account: account, user: user) }

  describe "loud parse failure" do
    it "warns when the response carries no JSON object at all" do
      # o3-mini's actual failure shape: plausible prose, no JSON.
      expect(Rails.logger).to receive(:warn).with(/no JSON object/i)
      expect(service.send(:parse_brief_json, "Sure — I'd provision two nodes for you.")).to be_nil
    end

    it "includes an excerpt so the failure is diagnosable from the log alone" do
      expect(Rails.logger).to receive(:warn).with(/Sure — I'd provision/)
      service.send(:parse_brief_json, "Sure — I'd provision two nodes for you.")
    end

    it "still warns (and returns nil) on malformed JSON" do
      allow(Rails.logger).to receive(:warn)
      expect(service.send(:parse_brief_json, "{ not valid json")).to be_nil
    end

    it "stays quiet and parses on a good payload" do
      expect(Rails.logger).not_to receive(:warn)
      expect(service.send(:parse_brief_json, '{"intent":"x"}')).to eq("intent" => "x")
    end
  end

  describe "structured-output contract blocks model substitution" do
    let!(:agent) do
      create(:ai_agent, account: account, creator: user, status: "active").tap do |a|
        a.update_column(:slug, "intent-classifier")
      end
    end

    let(:substituted) do
      instance_double(::Ai::Routing::TaskTierResolver::Resolution,
                      model: "o3-mini", effort: nil, tier: :standard, baseline_model: "gpt-4o")
    end
    let(:decision) { instance_double(::Ai::RoutingDecision, id: "rd-1") }
    let(:response) do
      instance_double("WorkerLlmResponse", success?: true, content: '{"intent":"x"}',
                                           prompt_tokens: 1, completion_tokens: 1, cached_tokens: 0,
                                           total_tokens: 2, model: "m", provider: "p")
    end
    let(:client) { instance_double(::TrackedWorkerLlmClient) }

    before do
      allow(service).to receive(:llm_client).and_return(client)
      allow(::Ai::Routing::TaskTierResolver).to receive(:enabled_for?).and_return(true)
      allow(::Ai::Routing::TaskTierResolver).to receive(:resolve).and_return(substituted)
      allow(substituted).to receive(:persist!).and_return(decision)
      allow(decision).to receive(:id).and_return("rd-1")
    end

    it "does NOT send the substituted model when the caller needs structured output" do
      allow(service).to receive(:annotate_unapplied_resolution!)
      expect(client).to receive(:complete)
        .with(hash_including(model: service.send(:resolve_model))).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "never sends o3-mini specifically" do
      allow(service).to receive(:annotate_unapplied_resolution!)
      expect(client).to receive(:complete) { |**kw|
        expect(kw[:model]).not_to eq("o3-mini")
        response
      }
      service.capture(natural_language: "provision a node")
    end

    it "still RECORDS the decision — the oracle keeps its data" do
      allow(service).to receive(:annotate_unapplied_resolution!)
      expect(::Ai::Routing::TaskTierResolver).to receive(:resolve).and_return(substituted)
      allow(client).to receive(:complete).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    it "annotates the decision as considered-but-not-applied, with a reason" do
      expect(service).to receive(:annotate_unapplied_resolution!)
        .with(anything, hash_including(:reason))
      allow(client).to receive(:complete).and_return(response)
      service.capture(natural_language: "provision a node")
    end

    context "when the resolution does NOT substitute (same as baseline)" do
      let(:same) do
        instance_double(::Ai::Routing::TaskTierResolver::Resolution,
                        model: "gpt-4o", effort: nil, tier: :reasoning, baseline_model: "gpt-4o")
      end

      before do
        allow(::Ai::Routing::TaskTierResolver).to receive(:resolve).and_return(same)
        allow(same).to receive(:persist!).and_return(decision)
      end

      it "applies it — there is no substitution to be unsafe about" do
        expect(client).to receive(:complete).with(hash_including(model: "gpt-4o")).and_return(response)
        service.capture(natural_language: "provision a node")
      end
    end
  end
end
