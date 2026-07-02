# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Context::CompressionService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#compress_entries' do
    context 'with empty entries' do
      it 'returns entries unchanged with zero counts' do
        result = service.compress_entries(entries: [], token_budget: 100)

        expect(result[:entries]).to eq([])
        expect(result[:compressed]).to eq(0)
        expect(result[:original_tokens]).to eq(0)
        expect(result[:compressed_tokens]).to eq(0)
      end
    end

    context 'when entries fit within token budget' do
      let(:entries) do
        [{ content: "Short text." }]
      end

      it 'returns entries unchanged' do
        result = service.compress_entries(entries: entries, token_budget: 1000)

        expect(result[:entries]).to eq(entries)
        expect(result[:compressed]).to eq(0)
      end
    end

    context 'when entries exceed token budget' do
      let(:long_content) { "This is a long sentence. " * 200 }
      let(:short_content) { "Short." }
      let(:entries) do
        [
          { content: long_content },
          { content: short_content }
        ]
      end

      before do
        # Stub LLM compression to nil so it falls back to extractive
        allow(service).to receive(:find_economy_client).and_return(nil)
      end

      it 'compresses entries exceeding MAX_ENTRY_TOKENS' do
        result = service.compress_entries(entries: entries, token_budget: 10)

        expect(result[:compressed]).to be >= 1
        expect(result[:entries].size).to eq(2)
      end

      it 'marks compressed entries with metadata' do
        result = service.compress_entries(entries: entries, token_budget: 10)

        compressed_entry = result[:entries].first
        expect(compressed_entry[:metadata]).to include(compressed: true)
      end
    end
  end

  describe '#compress_single' do
    context 'when content is short enough' do
      let(:entry) { { content: "Short text." } }

      it 'returns entry unchanged' do
        result = service.compress_single(entry)
        expect(result).to eq(entry)
      end
    end

    context 'when LLM compression succeeds' do
      let(:long_content) { "This is a detailed sentence about topic A. " * 100 }
      let(:entry) { { content: long_content, metadata: {} } }
      let(:llm_client) { instance_double(WorkerLlmClient) }
      let(:economy_agent) { instance_double(Ai::Agent, resolved_model: "test-model") }

      before do
        allow(service).to receive(:find_economy_client).and_return(llm_client)
        service.instance_variable_set(:@economy_agent, economy_agent)
        allow(llm_client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "Compressed version.", usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 })
        )
      end

      it 'uses LLM compression and marks metadata' do
        result = service.compress_single(entry)

        expect(result[:content]).to eq("Compressed version.")
        expect(result[:metadata][:compressed]).to be true
        expect(result[:metadata][:original_length]).to eq(long_content.length)
      end

      it 'calls the LLM with the resolved agent model' do
        expect(llm_client).to receive(:complete).with(hash_including(model: "test-model")).and_return(
          Ai::Llm::Response.new(content: "Compressed version.", usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 })
        )
        service.compress_single(entry)
      end
    end

    context 'when no economy agent is available' do
      let(:long_content) { "This is a detailed sentence about topic A. " * 100 }
      let(:entry) { { content: long_content, metadata: {} } }

      before do
        allow(service).to receive(:find_economy_client).and_return(nil)
      end

      it 'falls back to extractive compression' do
        result = service.compress_single(entry)
        expect(result[:metadata][:compression_method]).to eq("extractive")
      end
    end

    context 'when LLM compression fails' do
      let(:long_content) { "First sentence about cats. Second sentence about dogs. Third about birds. Fourth about fish. " * 30 }
      let(:entry) { { content: long_content, metadata: {} } }

      before do
        allow(service).to receive(:find_economy_client).and_return(nil)
      end

      it 'falls back to extractive compression' do
        result = service.compress_single(entry)

        expect(result[:metadata][:compressed]).to be true
        expect(result[:metadata][:compression_method]).to eq("extractive")
        expect(result[:content].length).to be < long_content.length
      end

      it 'preserves at least one sentence' do
        result = service.compress_single(entry)
        expect(result[:content]).not_to be_empty
      end
    end

    context 'when LLM raises an error' do
      let(:long_content) { "Sentence one here. Sentence two here. " * 100 }
      let(:entry) { { content: long_content } }
      let(:llm_client) { instance_double(WorkerLlmClient) }
      let(:economy_agent) { instance_double(Ai::Agent, resolved_model: "test-model") }

      before do
        allow(service).to receive(:find_economy_client).and_return(llm_client)
        service.instance_variable_set(:@economy_agent, economy_agent)
        allow(llm_client).to receive(:complete).and_raise(StandardError.new("API error"))
      end

      it 'falls back to extractive compression' do
        result = service.compress_single(entry)

        expect(result[:metadata][:compression_method]).to eq("extractive")
      end
    end
  end

  describe "governed tier routing (campaign 019f2163 inc4)" do
    let(:agent) { create(:ai_agent, account: account, agent_type: "assistant") }
    let(:llm_client) { instance_double(WorkerLlmClient) }
    let(:long_content) { "This is a detailed sentence about topic A. " * 100 }
    let(:entry) { { content: long_content, metadata: {} } }

    before do
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5")
      allow(service).to receive(:find_economy_client).and_return(llm_client)
      service.instance_variable_set(:@economy_agent, agent)
    end

    context "gate OFF (default)" do
      it "never invokes the tier resolver and calls the LLM with the agent's baseline model" do
        expect(Ai::Routing::TaskTierResolver).not_to receive(:resolve)
        expect(llm_client).to receive(:complete).with(hash_including(model: "claude-sonnet-5")).and_return(
          Ai::Llm::Response.new(content: "Compressed.", usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
        )
        service.compress_single(entry)
      end
    end

    context "gate ON" do
      before { account.update!(settings: { "ai_task_tier_routing_enabled" => true }) }

      it "classifies with the explicit summarization task_type and lands on a cheap (light/standard) tier" do
        allow(llm_client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "Compressed.", usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
        )
        expect_any_instance_of(Ai::Routing::TaskComplexityClassifierService)
          .to receive(:classify_preview)
          .with(hash_including(task_type: "summarization"))
          .and_return(
            complexity_level: "simple", complexity_score: 0.15, recommended_tier: "economy",
            signals: { token_density: 0.1, tool_complexity: 0.0, conversation_depth: 0.15,
                       content_complexity: 0.0, task_type_baseline: 0.35,
                       raw: { token_count: 50, tool_count: 0, message_count: 2 } },
            classifier_version: "1.0.0"
          )

        service.compress_single(entry)

        decision = Ai::RoutingDecision.last
        expect(decision).to be_present
        expect(%w[light standard]).to include(decision.model_tier)
        expect(decision.rationale["decision"]).not_to eq("escalate")
        expect(decision.rationale.dig("complexity", "task_type")).to eq("summarization")
      end
    end
  end
end
