# frozen_string_literal: true

require "rails_helper"

# IMP-bfc06c7663ce. ContentLinkService wrote nodes with entity_type "page" /
# "article" and edges with relation_type "references" — none of which were
# registered vocabulary, so every create! raised RecordInvalid and the whole
# wikilink graph was inert. Two blocking validations, not one; the readers
# filtered on the same unregistered values, so it failed silently rather than
# paging anyone.
#
# The repair could not simply register the vocabulary: pages, articles, skills,
# agents and teams all created node_type "entity" keyed by human-readable name,
# and (account_id, name, node_type) is uniquely indexed over active rows. That
# put free-form page TITLES into the shared entity namespace and produced a new
# silent regression — a page named like a skill made the skill lose its graph
# node entirely. Content nodes therefore get their OWN node_type, which moves
# them out of that namespace at exactly the key the index enforces.
RSpec.describe ContentLinkService do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  def page_node_for(page)
    Ai::KnowledgeGraphNode.find_by(account: account, entity_type: "page")
                          .then { |n| n if n&.metadata&.dig("content_id") == page.id }
  end

  # S5 — the regression floor: the two validations that made the feature inert.
  describe "the vocabulary the service writes is registered" do
    it "accepts a page node" do
      node = Ai::KnowledgeGraphNode.new(account: account, name: "P", node_type: "content",
                                        entity_type: "page", status: "active")
      expect(node).to be_valid
    end

    it "accepts an article node" do
      node = Ai::KnowledgeGraphNode.new(account: account, name: "A", node_type: "content",
                                        entity_type: "article", status: "active")
      expect(node).to be_valid
    end

    it "accepts a references edge" do
      a = Ai::KnowledgeGraphNode.create!(account: account, name: "A", node_type: "content",
                                         entity_type: "page", status: "active")
      b = Ai::KnowledgeGraphNode.create!(account: account, name: "B", node_type: "content",
                                         entity_type: "page", status: "active")
      edge = Ai::KnowledgeGraphEdge.new(account: account, source_node: a, target_node: b,
                                        relation_type: "references")
      expect(edge).to be_valid
    end
  end

  describe "content nodes live outside the entity namespace" do
    it "creates a page node at all (the original bug: it could not)" do
      page = create(:page, account: account, title: "Vector Search")

      expect { service.send(:find_or_create_page_node, page) }.not_to raise_error
      expect(page_node_for(page)).to be_present
    end

    it "gives it node_type content, not entity" do
      page = create(:page, account: account, title: "Vector Search")
      node = service.send(:find_or_create_page_node, page)

      expect(node.node_type).to eq("content")
    end

    # S1 — a page titled identically to a skill must not disturb the skill.
    it "coexists with a same-named skill node under the unique index" do
      skill_node = Ai::KnowledgeGraphNode.create!(account: account, name: "Vector Search",
                                                  node_type: "entity", entity_type: "skill",
                                                  status: "active")
      page = create(:page, account: account, title: "Vector Search")

      expect { service.send(:find_or_create_page_node, page) }.not_to raise_error
      expect(skill_node.reload.status).to eq("active")
      expect(Ai::KnowledgeGraphNode.where(account: account, name: "Vector Search",
                                          status: "active").count).to eq(2)
    end

    # S2, second order — the reproduced F6: this raised RecordNotUnique and
    # surfaced as a 500 from POST /extract_links.
    it "does not raise when a skill node already holds the name" do
      Ai::KnowledgeGraphNode.create!(account: account, name: "Shared Name",
                                     node_type: "entity", entity_type: "skill", status: "active")
      page = create(:page, account: account, title: "Shared Name")

      expect { service.send(:find_or_create_page_node, page) }
        .not_to raise_error
    end
  end

  # S2, first order — the reproduced F5, the regression that blocked this task:
  # with a page node holding the name first, sync_skill returned nil and the
  # skill silently got NO graph node, the unique-index violation swallowed by a
  # rescue into a warn log.
  describe "a pre-existing content node does not starve the skill bridge" do
    # Assert the COUNT, not sync_skill's return value: it returns nil even in
    # the healthy no-collision control (verified by probe), so a nil return
    # proves nothing. The count is what F5 actually measured — it was 0 when a
    # same-named page node occupied the entity slot.
    it "still gives the skill its own node" do
      page = create(:page, account: account, title: "Vector Search")
      service.send(:find_or_create_page_node, page)
      skill = create(:ai_skill, account: account, name: "Vector Search")

      Ai::SkillGraph::BridgeService.new(account: account).sync_skill(skill)

      expect(Ai::KnowledgeGraphNode.where(ai_skill_id: skill.id, status: "active").count).to eq(1)
    end

    it "leaves the content node intact alongside it" do
      page = create(:page, account: account, title: "Vector Search")
      service.send(:find_or_create_page_node, page)
      skill = create(:ai_skill, account: account, name: "Vector Search")

      Ai::SkillGraph::BridgeService.new(account: account).sync_skill(skill)

      expect(page_node_for(page)).to be_present
      expect(Ai::KnowledgeGraphNode.where(account: account, name: "Vector Search",
                                          status: "active").count).to eq(2)
    end
  end
end
