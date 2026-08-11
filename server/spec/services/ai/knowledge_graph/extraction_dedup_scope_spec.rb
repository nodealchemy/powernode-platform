# frozen_string_literal: true

require "rails_helper"

# 019ff111. #find_or_create_node only ever creates node_type "entity", and its two
# NAME-based dedup paths both constrain node_type = 'entity' explicitly. The
# EMBEDDING dedup path did not: it drew candidates from every active node in the
# account, then called record_mention! on the winner and RETURNED it as the
# extracted entity's node.
#
# So a semantically similar node of a different KIND could be adopted as an
# entity — its mention_count bumped and extractor edges hung off it. This already
# applied to skill nodes (node_type "entity", embedded by the skill-graph bridge);
# it became reachable for CONTENT nodes when IMP-bfc06c7663ce registered
# node_type "content" for pages/articles, which carry embeddings via
# generate_page_embedding!.
RSpec.describe Ai::KnowledgeGraph::ExtractionService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  # Identical vectors => cosine distance 0, comfortably inside
  # (1.0 - DEDUP_THRESHOLD) = 0.08, so this node WOULD be adopted if it were ever
  # a candidate. That makes the assertions about scoping, not about distance.
  let(:vector) { Array.new(1536, 0.05) }
  let(:entity) do
    { "name" => "Vector Search", "type" => "technology",
      "description" => "A retrieval technique using embeddings." }
  end
  let(:stats) { Hash.new(0) }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(vector)
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
  end

  def find_or_create
    service.send(:find_or_create_node, entity, document: nil, existing_nodes: {}, stats: stats)
  end

  context "when a CONTENT node is the nearest neighbour" do
    let!(:content_node) do
      Ai::KnowledgeGraphNode.create!(
        account: account, name: "Vector Search Explained", node_type: "content",
        entity_type: "page", status: "active", confidence: 1.0, mention_count: 0,
        embedding: vector, metadata: { "content_type" => "page", "content_id" => SecureRandom.uuid }
      )
    end

    it "does not adopt it as the extracted entity" do
      expect(find_or_create).not_to eq(content_node)
    end

    it "creates a real entity node instead" do
      node = find_or_create

      expect(node).to be_present
      expect(node.node_type).to eq("entity")
    end

    it "leaves the content node's mention_count untouched" do
      expect { find_or_create }.not_to change { content_node.reload.mention_count }
    end
  end

  context "when an ENTITY node is the nearest neighbour" do
    let!(:entity_node) do
      Ai::KnowledgeGraphNode.create!(
        account: account, name: "Vector Retrieval", node_type: "entity",
        entity_type: "technology", status: "active", confidence: 1.0, mention_count: 0,
        embedding: vector
      )
    end

    # The control: narrowing the candidate scope must not break the dedup this
    # path exists to perform.
    it "still dedups against it" do
      expect(find_or_create).to eq(entity_node)
    end

    it "still records the mention" do
      expect { find_or_create }.to change { entity_node.reload.mention_count }.by(1)
    end
  end
end
