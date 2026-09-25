# frozen_string_literal: true

require "rails_helper"

# D5 — the prompt an agent is SERVED decides which skill version gets credit.
#
# Before D5 the serving path read ai_skills.system_prompt and nothing else, so
# an A/B variant was never served at all, while EvolutionService#record_outcome
# credited it on a coin flip. Routing now happens here, where the prompt is
# built, and the versions whose text actually went out are recorded so the
# caller can stamp them onto the execution.
RSpec.describe Ai::Agent, "served skill versions" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:skill) do
    create(:ai_skill, account: account, status: "active", is_enabled: true, system_prompt: "the active text")
  end
  let!(:active) do
    create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0",
                              is_active: true, system_prompt: "the active text")
  end
  let!(:variant) do
    create(:ai_skill_version, account: account, ai_skill: skill, version: "2.0.0",
                              is_active: false, is_ab_variant: true, ab_traffic_pct: 0.5,
                              system_prompt: "the variant text")
  end

  before do
    Ai::AgentSkill.create!(ai_agent_id: agent.id, ai_skill_id: skill.id, is_active: true, priority: 1)
  end

  # Pins the router's draw without stubbing Random for the whole process.
  def build_with(draw)
    allow(Ai::SkillGraph::EvolutionService).to receive(:route_served_versions).and_wrap_original do |original, ids, **|
      original.call(ids, random: instance_double(Random, rand: draw))
    end
    agent.send(:build_skill_system_prompts)
  end

  it "serves the variant's own text, and names the variant, inside its share" do
    prompt = build_with(0.1)

    expect(prompt).to include("the variant text")
    expect(prompt).not_to include("the active text")
    expect(agent.served_skill_version_ids).to eq([ variant.id ])
  end

  it "serves the skill's own text, and names the active version, outside it" do
    prompt = build_with(0.9)

    expect(prompt).to include("the active text")
    expect(prompt).not_to include("the variant text")
    expect(agent.served_skill_version_ids).to eq([ active.id ])
  end

  it "does not name a version whose prompt the token budget dropped" do
    # A dropped prompt never reached the model, so crediting its version with
    # the run's outcome would be crediting text that was not served.
    account.update!(settings: (account.settings || {}).merge(Ai::Agent::SKILL_PROMPT_TOKEN_BUDGET_SETTING => 1))

    expect(build_with(0.9)).to eq("")
    expect(agent.served_skill_version_ids).to eq([])
  end

  # C11: a per-call draw rebuilt the system prompt between turns of one
  # conversation. With a draw_key the draw is fixed per (conversation, skill).
  describe "draw_key (one draw per conversation)" do
    it "serves the same skill text on every build for one conversation" do
      key = SecureRandom.uuid
      prompts = Array.new(5) { agent.build_system_prompt_with_profile(draw_key: key) }

      expect(prompts.uniq.size).to eq(1)
    end

    it "still splits traffic across conversations" do
      served = Array.new(40) { agent.send(:build_skill_system_prompts, draw_key: SecureRandom.uuid) }

      expect(served.any? { |p| p.include?("the variant text") }).to be(true)
      expect(served.any? { |p| p.include?("the active text") }).to be(true)
    end
  end

  it "names nothing before any prompt is built" do
    expect(described_class.new.served_skill_version_ids).to eq([])
  end
end
