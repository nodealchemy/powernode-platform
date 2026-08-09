# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraph::ExtractionService, type: :service do
  let(:account) { create(:account) }
  let(:kb) { create(:ai_knowledge_base, account: account) }
  subject(:service) { described_class.new(account) }

  describe "#extract_from_document" do
    let(:document) do
      Ai::Document.create!(
        knowledge_base: kb,
        name: "Test Doc",
        source_type: "upload",
        content: "Ruby on Rails is a web framework created by David Heinemeier Hansson. " \
                 "Rails uses the Ruby programming language. " \
                 "PostgreSQL is a popular database used with Rails applications. " \
                 "The Active Record pattern is a core part of Rails.",
        status: "indexed"
      )
    end

    it "extracts entities and relations from document content" do
      result = service.extract_from_document(document: document)

      expect(result).to have_key(:nodes)
      expect(result).to have_key(:edges)
      expect(result).to have_key(:stats)
      expect(result[:stats][:nodes_created]).to be >= 0
    end

    it "raises error for document with no content" do
      empty_doc = Ai::Document.create!(
        knowledge_base: kb,
        name: "Empty Doc",
        source_type: "upload",
        content: nil,
        status: "pending"
      )

      expect {
        service.extract_from_document(document: empty_doc)
      }.to raise_error(Ai::KnowledgeGraph::ExtractionServiceError, /no content/)
    end

    it "deduplicates nodes with same name" do
      # Create existing node
      create(:ai_knowledge_graph_node, account: account, name: "Ruby", node_type: "entity")

      doc = Ai::Document.create!(
        knowledge_base: kb,
        name: "Ruby Doc",
        source_type: "upload",
        content: "Ruby is a programming language. Ruby was created by Yukihiro Matsumoto.",
        status: "indexed"
      )

      result = service.extract_from_document(document: doc)

      # Should have found existing node
      expect(result[:stats][:nodes_existing]).to be >= 0
    end

    context "with short content" do
      let(:short_doc) do
        Ai::Document.create!(
          knowledge_base: kb,
          name: "Short Doc",
          source_type: "upload",
          content: "Python uses Django framework.",
          status: "indexed"
        )
      end

      it "handles short content without chunking" do
        result = service.extract_from_document(document: short_doc)
        expect(result[:stats]).to be_present
      end
    end
  end

  describe "governed tier routing (campaign 019f2163 inc4)" do
    let(:agent) { create(:ai_agent, account: account, agent_type: "assistant") }
    let(:client) { instance_double(WorkerLlmClient) }

    before do
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5")
      allow(service).to receive(:build_llm_clients).and_return([[client, "claude-sonnet-5", agent]])
      allow(client).to receive(:provider_name).and_return("anthropic")
    end

    context "gate OFF (default)" do
      it "never invokes the tier resolver and calls the LLM with the pre-resolved baseline model" do
        expect(Ai::Routing::TaskTierResolver).not_to receive(:resolve)
        expect(client).to receive(:complete_structured).with(hash_including(model: "claude-sonnet-5")).and_return(
          Ai::Llm::Response.new(content: '{"entities": [], "relations": []}',
                                 usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
        )
        service.extract_from_text(text: "Ruby uses Rails.")
      end
    end

    context "gate ON" do
      before { account.update!(settings: { "ai_task_tier_routing_enabled" => true }) }

      it "classifies with the explicit extraction task_type and lands on a cheap (light/standard) tier" do
        allow(client).to receive(:complete_structured).and_return(
          Ai::Llm::Response.new(content: '{"entities": [], "relations": []}',
                                 usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
        )
        expect_any_instance_of(Ai::Routing::TaskComplexityClassifierService)
          .to receive(:classify_preview)
          .with(hash_including(task_type: "extraction"))
          .and_return(
            complexity_level: "simple", complexity_score: 0.15, recommended_tier: "economy",
            signals: { token_density: 0.1, tool_complexity: 0.0, conversation_depth: 0.15,
                       content_complexity: 0.0, task_type_baseline: 0.15,
                       raw: { token_count: 40, tool_count: 0, message_count: 2 } },
            classifier_version: "1.0.0"
          )

        service.extract_from_text(text: "Ruby uses Rails.")

        decision = Ai::RoutingDecision.last
        expect(decision).to be_present
        expect(%w[light standard]).to include(decision.model_tier)
        expect(decision.rationale["decision"]).not_to eq("escalate")
        expect(decision.rationale.dig("complexity", "task_type")).to eq("extraction")
      end
    end

    # This seam's output contract is structured JSON (EXTRACTION_SCHEMA) — the
    # same shape that broke intent capture when a reasoning-tier substitution
    # answered in prose. A resolution that would substitute a different model is
    # declined (baseline sent, decision annotated considered-but-not-applied);
    # a non-substituting resolution still applies. Mirrors
    # intent_capture_tier_routing_spec.rb / intent_capture_contract_spec.rb.
    context "gate ON with a SUBSTITUTING resolution (structured-output guard)" do
      let(:response) do
        Ai::Llm::Response.new(content: '{"entities": [], "relations": []}',
                               usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
      end
      let(:resolution) do
        instance_double(Ai::Routing::TaskTierResolver::Resolution,
                        model: "some-reasoning-model", effort: "high", tier: :reasoning,
                        baseline_model: "claude-sonnet-5")
      end

      before do
        account.update!(settings: { "ai_task_tier_routing_enabled" => true })
        allow(service).to receive(:resolve_task_tier).and_return(resolution)
        allow(service).to receive(:routing_decision_id).and_return("rd-123")
        allow(service).to receive(:annotate_unapplied_resolution!)
      end

      it "declines the substitution — sends the baseline model without the resolver's effort" do
        expect(client).to receive(:complete_structured) do |**opts|
          expect(opts[:model]).to eq("claude-sonnet-5")
          expect(opts[:effort]).to be_nil
          response
        end
        service.extract_from_text(text: "Ruby uses Rails.")
      end

      it "annotates the decision as considered-but-not-applied, with the delivered model" do
        allow(client).to receive(:complete_structured).and_return(response)
        expect(service).to receive(:annotate_unapplied_resolution!) do |id, reason:, delivered_model:|
          expect(id).to eq("rd-123")
          expect(reason).to match(/structured/i)
          expect(delivered_model).to eq("claude-sonnet-5")
        end
        service.extract_from_text(text: "Ruby uses Rails.")
      end

      it "still links the routing decision to the execution the call creates" do
        expect(client).to receive(:complete_structured)
          .with(hash_including(routing_decision_id: "rd-123")).and_return(response)
        service.extract_from_text(text: "Ruby uses Rails.")
      end
    end

    context "gate ON with a NON-substituting resolution" do
      let(:response) do
        Ai::Llm::Response.new(content: '{"entities": [], "relations": []}',
                               usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
      end
      let(:resolution) do
        instance_double(Ai::Routing::TaskTierResolver::Resolution,
                        model: "claude-sonnet-5", effort: "low", tier: :light,
                        baseline_model: "claude-sonnet-5")
      end

      before do
        account.update!(settings: { "ai_task_tier_routing_enabled" => true })
        allow(service).to receive(:resolve_task_tier).and_return(resolution)
        allow(service).to receive(:routing_decision_id).and_return("rd-456")
      end

      it "applies the resolution's model and effort" do
        expect(client).to receive(:complete_structured)
          .with(hash_including(model: "claude-sonnet-5", effort: "low")).and_return(response)
        service.extract_from_text(text: "Ruby uses Rails.")
      end
    end
  end
end
