# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the "Powernode Frontend Developer" platform agent
# (React/TypeScript specialist for frontend/). The agent is fully specified in
# ai_dev_team_seed.rb but was found absent from the live account despite the
# seed defining it — a data/deployment gap, not a missing feature. This spec
# locks the seed's agent-creation behavior in place and proves the seed ->
# Claude Code mirror pipeline (Ai::ClaudeExport::AgentSkeletonSync / `rake
# claude:sync_agents`) produces a skeleton once the agent exists, with no
# changes needed on the sync side — it is generic over any active,
# non-mcp_client agent (see agent_skeleton_sync_spec.rb).
RSpec.describe "ai_dev_team_seed frontend developer agent" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }

  # Pre-seed two of the skills the seed assigns to the Frontend Developer — the
  # assignment loop silently `next unless skill` on a missing slug, so without
  # these the attachment step has nothing to link.
  let!(:code_review_skill)     { create(:ai_skill, account: account, slug: "code-review") }
  let!(:code_generation_skill) { create(:ai_skill, account: account, slug: "code-generation") }

  def frontend_developer
    Ai::Agent.find_by(account: account, name: "Powernode Frontend Developer")
  end

  it "creates the Frontend Developer agent with the React/TypeScript system prompt" do
    load_seed!("ai_dev_team_seed.rb")

    agent = frontend_developer
    expect(agent).to be_present
    expect(agent.agent_type).to eq("code_assistant")
    expect(agent.ai_provider_id).to eq(anthropic.id)
    expect(agent.status).to eq("active")
    expect(agent.slug).to eq("powernode-frontend-developer")

    prompt = agent.mcp_metadata["system_prompt"]
    expect(prompt).to include("currentUser?.permissions?.includes")
    expect(prompt).to include("NEVER use roles for access control")
    expect(prompt).to include("bg-theme-")
    expect(prompt).to include("PageContainer")
    expect(prompt).to include("Vite")
    expect(prompt).to include("npx tsc --noEmit")
    expect(prompt).to include("Jest")
  end

  it "attaches the assigned skills as active agent skills" do
    load_seed!("ai_dev_team_seed.rb")

    expect(frontend_developer.skill_slugs).to include("code-review", "code-generation")
  end

  it "is picked up by the Claude Code skeleton sync with no sync-side changes" do
    load_seed!("ai_dev_team_seed.rb")
    agent = frontend_developer

    target_dir = Dir.mktmpdir("frontend-developer-sync-spec")
    begin
      Ai::ClaudeExport::AgentSkeletonSync.new(account: account, target_dir: target_dir).sync!

      path = File.join(target_dir, "powernode-frontend-developer.md")
      expect(File.exist?(path)).to be true

      content = File.read(path)
      expect(content).to include(%(agent_id: "#{agent.id}"))
      expect(content).to include("mcp__powernode__platform_get_agent")
      expect(content).to include("code-review")
    ensure
      FileUtils.remove_entry(target_dir) if File.exist?(target_dir)
    end
  end
end
