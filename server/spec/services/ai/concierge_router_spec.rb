# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ConciergeRouter do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, provider_type: "openai") }
  let(:assistant_agent) do
    create(:ai_agent, account: account, provider: provider, agent_type: "assistant", status: "active")
  end
  let(:conversation) do
    create(:ai_conversation, account: account, user: user, agent: assistant_agent, provider: provider, status: "active")
  end
  let(:user_message) { Struct.new(:body).new("stand up a new infrastructure stack with sdwan") }

  subject(:router) { described_class.new(conversation: conversation, user_message: user_message) }

  describe "#route — provisioning entry-skill delegation" do
    let(:concierge) do
      create(:ai_agent, account: account, provider: provider, agent_type: "assistant",
             name: "System Concierge", status: "active")
    end

    let(:entry_skill) do
      create(:ai_skill, account: account, slug: "system-provision-infrastructure",
             name: "Provision Infrastructure", category: "devops", status: "active",
             metadata: { "domain" => "system", "invocation_mode" => "workflow_step", "entry_point" => true })
    end

    before do
      create(:ai_agent_skill, agent: concierge, skill: entry_skill, is_active: true)
      # Bypass embedding-based discovery: assert the routing DECISION given the
      # discovered skill. (Embeddings are generated async and are not the unit
      # under test here.)
      allow(router).to receive(:discover_relevant_skills).and_return([ entry_skill ])
    end

    it "delegates a provisioning intent to the bound System Concierge specialist" do
      result = router.route
      expect(result.mode).to eq(:delegated)
      expect(result.delegated_agent).to eq(concierge)
    end

    it "exposes the routing signals that make delegation fire" do
      expect(entry_skill.workflow_step?).to be true
      expect(entry_skill.domain).to eq("system")
      expect(entry_skill.specialist_agent).to eq(concierge)
    end

    # Regression for the exact gap this increment closed: before binding the
    # entry skill to an assistant, provisioning skills were bound only to
    # monitor agents (e.g. Fleet Autonomy), so specialist_agent returned nil
    # and the router silently fell through to passthrough — provisioning never
    # got delegated to a chat agent.
    context "when the entry skill is bound only to a non-assistant (monitor) agent" do
      let(:fleet_monitor) do
        create(:ai_agent, account: account, provider: provider, agent_type: "monitor",
               name: "Fleet Autonomy", status: "active")
      end

      before do
        Ai::AgentSkill.where(skill: entry_skill).destroy_all
        create(:ai_agent_skill, agent: fleet_monitor, skill: entry_skill, is_active: true)
      end

      it "does not delegate (no assistant specialist) and falls through to passthrough" do
        expect(entry_skill.specialist_agent).to be_nil
        expect(router.route.mode).to eq(:passthrough)
      end
    end
  end

  # Capability skills (Ai::Skills::Contract) carry no executor and no agent
  # binding: the assembler, not this router, selects them. They must be
  # invisible to routing — excluded before the nearest-neighbour LIMIT, so any
  # number of them ranked first can neither suppress nor crowd out what the
  # router did before they existed. Real nodes and embeddings, not a stubbed
  # discovery.
  describe "#route — executor-less capability skills ranked first" do
    let(:concierge) do
      create(:ai_agent, account: account, provider: provider, agent_type: "assistant", name: "System Concierge", status: "active")
    end

    # Query = e0; a node at rank r sits at angle 0.04·r from it (cosine
    # distance well under the router's 0.85 cut-off), so rank order is exact.
    def vector_at(rank)
      Array.new(1536, 0.0).tap do |v|
        v[0] = Math.cos(0.04 * rank)
        v[1 + rank] = Math.sin(0.04 * rank)
      end
    end

    def skill_with_node(slug, rank, metadata:)
      skill = create(:ai_skill, account: account, slug: slug, name: slug.titleize, category: "productivity", status: "active")
      skill.update_columns(metadata: metadata)
      create(:ai_knowledge_graph_node, account: account, name: slug.titleize, entity_type: "skill", node_type: "entity",
                                       ai_skill_id: skill.id).set_embedding!(vector_at(rank))
      skill
    end

    def capability(slug, rank)
      skill_with_node(slug, rank, metadata: { "capability" => slug, "domain" => "websites" })
    end

    def legacy(slug, rank, mode: "one_shot", domain: "platform")
      skill_with_node(slug, rank, metadata: { "domain" => domain, "invocation_mode" => mode })
    end

    before do
      allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(vector_at(0))
    end

    it "still delegates to the specialist bound to the first legacy skill, however many capability skills rank above it" do
      10.times { |i| capability("capability-#{i}", i) }
      entry = legacy("system-provision-infrastructure", 10, mode: "workflow_step", domain: "system")
      create(:ai_agent_skill, agent: concierge, skill: entry, is_active: true)

      result = router.route
      expect(result.mode).to eq(:delegated)
      expect(result.delegated_agent).to eq(concierge)
    end

    it "still auto-invokes the first legacy skill's executor" do
      capability("capability-a", 0)
      answer = legacy("legacy-answer", 1)
      allow(router).to receive(:auto_invokable?).and_return(false)
      allow(router).to receive(:auto_invokable?).with(answer).and_return(true)
      allow(router).to receive(:invoke_skill).with(answer, anything).and_return({ success: true, data: {} })
      allow(router).to receive(:format_for_llm).and_return("ctx")

      result = router.route
      expect(result.mode).to eq(:invoked)
      expect(result.skill_slug).to eq("legacy-answer")
    end

    it "caps the candidates at ROUTER_TOP_K" do
      7.times { |i| legacy("legacy-#{i}", i) }
      expect(router.send(:discover_relevant_skills, "anything").size).to eq(described_class::ROUTER_TOP_K)
    end

    it "keeps the legacy-only candidate set and order exactly as before (no backfill past K)" do
      7.times { |i| legacy("legacy-#{i}", i) }
      expect(router.send(:discover_relevant_skills, "anything").map(&:slug)).to eq(%w[legacy-0 legacy-1 legacy-2 legacy-3 legacy-4])
    end

    it "keeps a capability skill that names an executor routable" do
      skill_with_node("capability-with-executor", 0,
                      metadata: { "capability" => "capability-with-executor", "domain" => "websites", "executor_class" => "SomeExecutor" })
      legacy("legacy-1", 1)
      expect(router.send(:discover_relevant_skills, "anything").map(&:slug)).to eq(%w[capability-with-executor legacy-1])
    end

    it "does not give a top-K slot to a node with no skill" do
      create(:ai_knowledge_graph_node, account: account, name: "Orphan Node", entity_type: "skill", node_type: "entity",
                                       ai_skill_id: nil).set_embedding!(vector_at(0))
      6.times { |i| legacy("legacy-#{i}", i + 1) }
      expect(router.send(:discover_relevant_skills, "anything").map(&:slug)).to eq(%w[legacy-0 legacy-1 legacy-2 legacy-3 legacy-4])
    end

    it "sees past capability rows interleaved among legacy ones, as if they did not exist" do
      legacy("legacy-0", 0)
      capability("capability-1", 1)
      legacy("legacy-2", 2)
      capability("capability-3", 3)
      %w[4 5 6 7].each { |r| legacy("legacy-#{r}", r.to_i) }
      expect(router.send(:discover_relevant_skills, "anything").map(&:slug)).to eq(%w[legacy-0 legacy-2 legacy-4 legacy-5 legacy-6])
    end
  end
end
