# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraphNode, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:knowledge_base).class_name("Ai::KnowledgeBase").optional }
    it { should belong_to(:source_document).class_name("Ai::Document").optional }
    it { should belong_to(:merged_into).class_name("Ai::KnowledgeGraphNode").optional }
    it { should have_many(:outgoing_edges).class_name("Ai::KnowledgeGraphEdge") }
    it { should have_many(:incoming_edges).class_name("Ai::KnowledgeGraphEdge") }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:node_type) }
    it { should validate_inclusion_of(:node_type).in_array(%w[entity concept relation attribute]) }
    it { should validate_inclusion_of(:entity_type).in_array(%w[person organization technology event location custom]).allow_nil }
    it { should validate_inclusion_of(:status).in_array(%w[active merged archived]) }
  end

  describe "scopes" do
    let!(:active_node) { create(:ai_knowledge_graph_node, account: account) }
    let!(:archived_node) { create(:ai_knowledge_graph_node, :archived, account: account) }
    let!(:concept_node) { create(:ai_knowledge_graph_node, :concept, account: account) }

    describe ".active" do
      it "returns only active nodes" do
        expect(described_class.active).to include(active_node, concept_node)
        expect(described_class.active).not_to include(archived_node)
      end
    end

    describe ".by_type" do
      it "filters by node type" do
        expect(described_class.by_type("entity")).to include(active_node)
        expect(described_class.by_type("entity")).not_to include(concept_node)
      end
    end

    describe ".by_entity_type" do
      it "filters by entity type" do
        results = described_class.by_entity_type("technology")
        expect(results).to include(active_node)
      end
    end

    describe ".search_by_name" do
      it "searches by name with ILIKE" do
        node = create(:ai_knowledge_graph_node, account: account, name: "Ruby on Rails")
        results = described_class.search_by_name("ruby")
        expect(results).to include(node)
      end
    end
  end

  describe "#connected_nodes" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account, name: "Node A") }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account, name: "Node B") }
    let(:node_c) { create(:ai_knowledge_graph_node, account: account, name: "Node C") }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b)
      create(:ai_knowledge_graph_edge, account: account, source_node: node_c, target_node: node_a,
                                       relation_type: "depends_on")
    end

    it "returns all connected nodes" do
      connected = node_a.connected_nodes
      expect(connected).to include(node_b, node_c)
    end
  end

  describe "#record_mention!" do
    let(:node) { create(:ai_knowledge_graph_node, account: account, mention_count: 5) }

    it "increments mention count and updates last_seen_at" do
      node.record_mention!
      node.reload
      expect(node.mention_count).to eq(6)
      expect(node.last_seen_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#merge_into!" do
    let(:node) { create(:ai_knowledge_graph_node, account: account) }
    let(:target) { create(:ai_knowledge_graph_node, account: account) }

    it "marks node as merged" do
      node.merge_into!(target)
      node.reload
      expect(node.status).to eq("merged")
      expect(node.merged_into_id).to eq(target.id)
    end
  end

  describe "#degree" do
    let(:node) { create(:ai_knowledge_graph_node, account: account) }

    it "returns sum of incoming and outgoing edges" do
      create(:ai_knowledge_graph_edge, account: account, source_node: node,
                                       target_node: create(:ai_knowledge_graph_node, account: account))
      create(:ai_knowledge_graph_edge, account: account,
                                       source_node: create(:ai_knowledge_graph_node, account: account),
                                       target_node: node, relation_type: "depends_on")

      expect(node.degree).to eq(2)
    end
  end

  describe "#decay_confidence!" do
    it "decays confidence based on age and decay_rate" do
      node = create(:ai_knowledge_graph_node, account: account,
                    confidence: 1.0, decay_rate: 0.1,
                    last_seen_at: 10.days.ago, updated_at: 10.days.ago)

      node.decay_confidence!
      node.reload

      # After 10 days with decay_rate=0.1: 1.0 * (0.9^10) ≈ 0.3487
      expect(node.confidence).to be < 0.4
      expect(node.confidence).to be > 0.3
    end

    it "floors confidence at 0.05" do
      node = create(:ai_knowledge_graph_node, account: account,
                    confidence: 0.1, decay_rate: 0.5,
                    last_seen_at: 30.days.ago, updated_at: 30.days.ago)

      node.decay_confidence!
      node.reload

      expect(node.confidence).to eq(0.05)
    end

    it "skips decay when decay_rate is zero" do
      node = create(:ai_knowledge_graph_node, account: account,
                    confidence: 0.8, decay_rate: 0.0,
                    last_seen_at: 30.days.ago)

      node.decay_confidence!
      node.reload

      expect(node.confidence).to eq(0.8)
    end

    it "skips decay when last seen less than 1 day ago" do
      node = create(:ai_knowledge_graph_node, account: account,
                    confidence: 0.8, decay_rate: 0.1,
                    last_seen_at: 6.hours.ago)

      node.decay_confidence!
      node.reload

      expect(node.confidence).to eq(0.8)
    end
  end

  describe "#recalculate_quality_score!" do
    it "computes weighted score from confidence, mentions, and connections" do
      node = create(:ai_knowledge_graph_node, account: account,
                    confidence: 0.8, mention_count: 10)

      # Add connections to increase degree
      3.times do
        target = create(:ai_knowledge_graph_node, account: account)
        create(:ai_knowledge_graph_edge, account: account, source_node: node, target_node: target)
      end

      node.recalculate_quality_score!
      node.reload

      expect(node.quality_score).to be > 0
      expect(node.quality_score).to be <= 1.0
      expect(node.last_quality_recalc_at).to be_within(2.seconds).of(Time.current)
    end

    it "sets higher score for nodes with more connections and mentions" do
      low_node = create(:ai_knowledge_graph_node, account: account,
                        confidence: 0.3, mention_count: 1)
      high_node = create(:ai_knowledge_graph_node, account: account,
                         confidence: 0.9, mention_count: 100)

      5.times do
        target = create(:ai_knowledge_graph_node, account: account)
        create(:ai_knowledge_graph_edge, account: account, source_node: high_node, target_node: target)
      end

      low_node.recalculate_quality_score!
      high_node.recalculate_quality_score!

      expect(high_node.reload.quality_score).to be > low_node.reload.quality_score
    end
  end
end
