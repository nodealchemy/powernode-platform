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
      # The skeleton fetches its prompt BY SLUG (HIER-P1B); the id is what
      # step 1 returns at run time, never a literal in the committed file.
      expect(content).to include(%(slug: "#{agent.slug}"))
      expect(content).to include("mcp__powernode__platform_get_agent")
      expect(content).to include("code-review")
    ensure
      FileUtils.remove_entry(target_dir) if File.exist?(target_dir)
    end
  end
  # HIER-P1 — the Knowledge Graph Curator is a GLOBAL canonical
  # (ai_utility_agents_seed.rb). The dev-team seed used to create a second,
  # account-scoped `data_analyst` copy; it now binds the canonical instead.
  describe "Knowledge Graph Curator (canonical rule)" do
    let!(:global_curator) do
      create(:ai_agent, account: nil, name: "Knowledge Graph Curator", slug: "knowledge-graph-curator",
                        agent_type: "assistant", is_system: true, source_key: "knowledge-graph-curator",
                        provider: ollama, creator: user)
    end

    it "does not seed an account-scoped duplicate" do
      load_seed!("ai_dev_team_seed.rb")

      expect(Ai::Agent.owned_by_account(account.id).where(name: "Knowledge Graph Curator")).to be_empty
      expect(Ai::Agent.where(name: "Knowledge Graph Curator").count).to eq(1)
    end

    it "binds the team's shared memory pool to the global canonical" do
      load_seed!("ai_dev_team_seed.rb")

      pool = Ai::MemoryPool.find_by(account: account, name: "Powernode Platform Conventions")
      expect(pool).to be_present
      expect(
        Ai::AgentConnection.exists?(account: account, connection_type: "shared_memory",
                                    source_type: "Ai::Agent", source_id: global_curator.id,
                                    target_type: "Ai::MemoryPool", target_id: pool.id)
      ).to be true
    end
  end

  # HIER-P2B-ENG — the Documentation Specialist was promoted from this seed's
  # account-scoped definition to a global canonical (ai_engineering_agents_seed).
  describe "Documentation Specialist (promoted to a global canonical)" do
    def team_role
      team = Ai::AgentTeam.find_by(account: account, name: "Powernode Development Team")
      Ai::TeamRole.find_by(agent_team: team, role_name: "Documentation Specialist")
    end

    it "never seeds an account-scoped 'Powernode Documentation Specialist' any more" do
      load_seed!("ai_dev_team_seed.rb")

      expect(Ai::Agent.owned_by_account(account.id).where(name: "Powernode Documentation Specialist")).to be_empty
      expect(Ai::Agent.where("name ILIKE ?", "%Documentation Specialist%")).to be_empty
    end

    it "skips the team role (no crash) when the canonical has not been seeded yet" do
      expect { load_seed!("ai_dev_team_seed.rb") }.not_to raise_error
      expect(team_role).to be_nil
      expect(frontend_developer).to be_present
    end

    it "binds the team role and membership to the global canonical when it exists" do
      global_documenter = create(:ai_agent, account: nil, name: "Documentation Specialist",
                                            slug: "documentation-specialist", agent_type: "content_generator",
                                            is_system: true, source_key: "documentation-specialist",
                                            provider: ollama, creator: user)

      load_seed!("ai_dev_team_seed.rb")

      expect(team_role.ai_agent_id).to eq(global_documenter.id)
      team = Ai::AgentTeam.find_by(account: account, name: "Powernode Development Team")
      expect(Ai::AgentTeamMember.exists?(ai_agent_team_id: team.id, ai_agent_id: global_documenter.id)).to be true
      # An account's MCP-server connection is never written onto the global row.
      expect(Ai::AgentConnection.where(source_type: "Ai::Agent", source_id: global_documenter.id,
                                       connection_type: "mcp_server")).to be_empty
    end
  end
end
