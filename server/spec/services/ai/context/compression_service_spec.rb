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
        allow(service).to receive(:find_economy_provider).and_return(nil)
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
      let(:provider_client) { double('provider_client') }

      before do
        allow(service).to receive(:find_economy_provider).and_return(provider_client)
        allow(provider_client).to receive(:generate).and_return({ content: "Compressed version." })
      end

      it 'uses LLM compression and marks metadata' do
        result = service.compress_single(entry)

        expect(result[:content]).to eq("Compressed version.")
        expect(result[:metadata][:compressed]).to be true
        expect(result[:metadata][:original_length]).to eq(long_content.length)
      end
    end

    context 'when LLM compression fails' do
      let(:long_content) { "First sentence about cats. Second sentence about dogs. Third about birds. Fourth about fish. " * 30 }
      let(:entry) { { content: long_content, metadata: {} } }

      before do
        allow(service).to receive(:find_economy_provider).and_return(nil)
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
      let(:provider_client) { double('provider_client') }

      before do
        allow(service).to receive(:find_economy_provider).and_return(provider_client)
        allow(provider_client).to receive(:generate).and_raise(StandardError.new("API error"))
      end

      it 'falls back to extractive compression' do
        result = service.compress_single(entry)

        expect(result[:metadata][:compression_method]).to eq("extractive")
      end
    end
  end
end
