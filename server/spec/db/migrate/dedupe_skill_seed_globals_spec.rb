# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20260704000001_dedupe_skill_seed_globals.rb")

# Exercises DedupeSkillSeedGlobals against the exact duplicate shape the
# since-fixed ai_skills_seed.rb bug produced in production: a GLOBAL
# (account_id nil, source_key set) skill coexisting with a pre-globalization
# ACCOUNT-scoped is_system row (source_key nil, cloned_from_id nil) sharing
# the same slug — the account row holding the real associations (agent
# bindings, MCP server links, KG node), the global row holding none.
RSpec.describe DedupeSkillSeedGlobals, type: :migration do
  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
  end

  describe "#up" do
    let(:account) { create(:account) }

    let!(:winner) do
      create(:ai_skill, :global, :system_skill, slug: "dup-test-skill",
                                                 source_key: "dup-test-skill", name: "Dup Test Skill")
    end
    let!(:loser) do
      create(:ai_skill, :system_skill, account: account, slug: "dup-test-skill",
                                        source_key: nil, cloned_from_id: nil, name: "Dup Test Skill (legacy)")
    end

    let!(:agent)       { create(:ai_agent, account: account) }
    let!(:agent_skill) { create(:ai_agent_skill, agent: agent, skill: loser) }
    let!(:kg_node) do
      create(:ai_knowledge_graph_node, account: account, ai_skill_id: loser.id)
    end
    let!(:mcp_server) { create(:mcp_server, account: account) }

    before { loser.update!(mcp_server_ids: [ mcp_server.id ]) }

    it "deletes the duplicate account-scoped row and keeps the global survivor" do
      described_class.new.up

      expect(Ai::Skill.where(id: loser.id)).not_to exist
      expect(Ai::Skill.where(slug: "dup-test-skill", is_system: true).count).to eq(1)
      expect(Ai::Skill.find(winner.id)).to be_present
    end

    it "reassigns the agent_skill from the loser to the survivor" do
      described_class.new.up

      expect(Ai::AgentSkill.where(ai_skill_id: loser.id)).not_to exist
      agent_skill.reload
      expect(agent_skill.ai_skill_id).to eq(winner.id)
    end

    it "moves the knowledge graph node onto the survivor" do
      described_class.new.up

      kg_node.reload
      expect(kg_node.ai_skill_id).to eq(winner.id)
    end

    it "reassigns MCP server links onto the survivor" do
      described_class.new.up

      winner.reload
      expect(winner.mcp_server_ids).to include(mcp_server.id)
    end

    it "does not orphan the agent_skill when the survivor already has one for the same agent" do
      create(:ai_agent_skill, agent: agent, skill: winner)

      described_class.new.up

      expect(Ai::AgentSkill.where(ai_agent_id: agent.id, ai_skill_id: winner.id).count).to eq(1)
      expect(Ai::AgentSkill.where(ai_skill_id: loser.id)).not_to exist
    end

    it "does not touch a real user clone sharing the same slug" do
      clone_account = create(:account)
      real_clone = create(:ai_skill, :system_skill, account: clone_account, slug: "dup-test-skill",
                                                      cloned_from_id: winner.id, name: "Dup Test Skill (clone)")

      described_class.new.up

      expect(Ai::Skill.where(id: real_clone.id)).to exist
      real_clone.reload
      expect(real_clone.account_id).to eq(clone_account.id)
      expect(real_clone.cloned_from_id).to eq(winner.id)
    end

    it "is idempotent (a second run is a no-op)" do
      described_class.new.up

      expect { described_class.new.up }
        .not_to change { Ai::Skill.where(slug: "dup-test-skill").count }
    end

    it "leaves unrelated, non-duplicated skills untouched" do
      solo = create(:ai_skill, :global, :system_skill, slug: "solo-skill", source_key: "solo-skill")

      described_class.new.up

      expect(Ai::Skill.where(id: solo.id)).to exist
    end
  end

  describe "#down" do
    it "is irreversible" do
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
