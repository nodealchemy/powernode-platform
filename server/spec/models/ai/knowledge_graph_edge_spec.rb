# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraphEdge, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:source_node).class_name("Ai::KnowledgeGraphNode") }
    it { should belong_to(:target_node).class_name("Ai::KnowledgeGraphNode") }
    it { should belong_to(:source_document).class_name("Ai::Document").optional }
  end

  describe "validations" do
    it { should validate_presence_of(:relation_type) }
    it do
      should validate_inclusion_of(:relation_type).in_array(
        %w[is_a has_a part_of related_to depends_on created_by used_by located_in similar_to causes precedes follows custom]
      )
    end
  end

  describe "scopes" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    let!(:active_edge) do
      create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b)
    end

    describe ".active" do
      it "returns active edges" do
        expect(described_class.active).to include(active_edge)
      end
    end

    describe ".by_relation" do
      it "filters by relation type" do
        edge = create(:ai_knowledge_graph_edge, :is_a, account: account,
                                                        source_node: create(:ai_knowledge_graph_node, account: account),
                                                        target_node: create(:ai_knowledge_graph_node, account: account))
        expect(described_class.by_relation("is_a")).to include(edge)
        expect(described_class.by_relation("is_a")).not_to include(active_edge)
      end
    end

    describe ".for_node" do
      it "returns edges for a given node (both directions)" do
        expect(described_class.for_node(node_a.id)).to include(active_edge)
        expect(described_class.for_node(node_b.id)).to include(active_edge)
      end
    end
  end

  describe "#opposite_node" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }
    let(:edge) { create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b) }

    it "returns target when given source" do
      expect(edge.opposite_node(node_a.id)).to eq(node_b)
    end

    it "returns source when given target" do
      expect(edge.opposite_node(node_b.id)).to eq(node_a)
    end
  end

  describe "#combined_score" do
    it "returns weight * confidence" do
      edge = build(:ai_knowledge_graph_edge, weight: 0.8, confidence: 0.9)
      expect(edge.combined_score).to be_within(0.001).of(0.72)
    end
  end
end
