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
      allow(router).to receive(:discover_relevant_skills).and_return([entry_skill])
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
end
