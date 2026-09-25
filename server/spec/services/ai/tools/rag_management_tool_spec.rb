# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::RagManagementTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:tool) { described_class.new(account: account, user: user) }

  describe ".definition" do
    # Search moved to query_knowledge_base; no remaining action reads these.
    it "does not advertise the parameters of the removed search action" do
      expect(described_class.definition[:parameters].keys).not_to include(:query, :mode, :top_k)
    end
  end

  describe "create_knowledge_base" do
    # The knowledge base's embedding model comes from the account's provider
    # catalog (Ai::RagService#resolve_embedding_config), never a literal in the
    # tool. The resolver is stubbed with an id no code carries, so the only way
    # it reaches the record is through the resolver.
    let(:resolved) do
      { embedding_model: "catalog-embedding-#{SecureRandom.hex(4)}", embedding_provider: "custom", embedding_dimensions: 768 }
    end

    let(:rag_service) { Ai::RagService.new(account) }

    before { allow(Ai::RagService).to receive(:new).with(account).and_return(rag_service) }

    it "takes the embedding model, provider and dimensions from the catalog resolver" do
      allow(rag_service).to receive(:resolve_embedding_config).and_return(resolved)

      result = tool.send(:call, { action: "create_knowledge_base", name: "Catalog KB" })

      expect(result[:success]).to be(true), result.inspect
      kb = account.ai_knowledge_bases.find(result[:knowledge_base][:id])
      expect(kb).to have_attributes(
        embedding_model: resolved[:embedding_model],
        embedding_provider: "custom",
        embedding_dimensions: 768
      )
    end

    it "refuses, and creates nothing, when the catalog has no embedding model" do
      allow(rag_service).to receive(:resolve_embedding_config)
        .and_raise(Ai::RagServiceError, "No embedding model is available")

      expect {
        result = tool.send(:call, { action: "create_knowledge_base", name: "No Model KB" })
        expect(result).to include(success: false, error: "No embedding model is available")
      }.not_to change(Ai::KnowledgeBase, :count)
    end
  end
end
