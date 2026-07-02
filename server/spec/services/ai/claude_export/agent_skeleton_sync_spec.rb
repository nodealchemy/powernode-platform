# frozen_string_literal: true

require "rails_helper"

# Frontmatter `description` is YAML-dumped (Psych folds/quotes long plain scalars
# across multiple physical lines), so multi-word assertions against it go through
# #frontmatter_of (parses the block, reconstructing the original unwrapped string)
# rather than a raw substring match against the file. The BODY is plain
# interpolated text (never YAML-dumped) so raw substring/include? checks against it
# are safe.
RSpec.describe Ai::ClaudeExport::AgentSkeletonSync, type: :service do
  let(:account) { create(:account) }
  let(:target_dir) { Dir.mktmpdir("claude-agent-sync-spec") }
  subject(:service) { described_class.new(account: account, target_dir: target_dir) }

  after { FileUtils.remove_entry(target_dir) if File.exist?(target_dir) }

  def build_agent(name:, resolved_model:, description: "Does helpful things.", skills: [])
    agent = create(:ai_agent, account: account, name: name, description: description)
    allow(agent).to receive(:resolved_model).and_return(resolved_model)
    skills.each do |slug|
      skill = create(:ai_skill, account: account, slug: slug)
      create(:ai_agent_skill, agent: agent, skill: skill, is_active: true)
    end
    agent
  end

  def stub_syncable(agents)
    allow(service).to receive(:syncable_agents).and_return(agents)
  end

  def path_for(agent)
    File.join(target_dir, "#{agent.slug}.md")
  end

  def content_for(agent)
    File.read(path_for(agent))
  end

  def frontmatter_of(content)
    _, fm, = content.split(/^---$/, 3)
    YAML.safe_load(fm)
  end

  # Ai::Agent.for_account already unions GLOBAL (account_id nil) rows with the
  # account's own — this documents/locks the design choice described in the
  # class comment: one query, account row wins a same-slug override.
  describe "#syncable_agents (account + global scope resolution)" do
    def build_global_agent(name:, description: nil)
      create(:ai_agent, :global, name: name, description: description)
    end

    it "includes GLOBAL platform agents and the account's own active agents" do
      global_agent = build_global_agent(name: "Global Helper")
      own_agent = create(:ai_agent, account: account, name: "My Own Agent")

      slugs = service.send(:syncable_agents).map(&:slug)

      expect(slugs).to include(global_agent.slug, own_agent.slug)
    end

    it "excludes inactive agents, whether global or account-owned" do
      inactive_own = create(:ai_agent, :inactive, account: account, name: "Paused Agent")

      slugs = service.send(:syncable_agents).map(&:slug)

      expect(slugs).not_to include(inactive_own.slug)
    end

    it "excludes another account's agents" do
      other_account = create(:account)
      other_agent = create(:ai_agent, account: other_account, name: "Someone Else's Agent")

      slugs = service.send(:syncable_agents).map(&:slug)

      expect(slugs).not_to include(other_agent.slug)
    end

    it "prefers the account's own override over the GLOBAL default when both share a slug" do
      global_agent = build_global_agent(name: "Code Reviewer", description: "Global default.")
      override = create(:ai_agent, account: account, name: "Code Reviewer", description: "Account override.")
      expect(override.slug).to eq(global_agent.slug) # sanity: same name -> same slug across scope partitions

      matches = service.send(:syncable_agents).select { |a| a.slug == override.slug }

      expect(matches.size).to eq(1)
      expect(matches.first.id).to eq(override.id)
    end
  end

  describe "frontmatter model mapping" do
    {
      light: %w[claude-haiku-4-5-20251001 haiku],
      standard: %w[claude-sonnet-4-6 sonnet],
      reasoning: %w[claude-opus-4-8 opus],
      frontier: %w[claude-fable-5 fable]
    }.each do |tier, (model_id, cc_model)|
      it "maps #{tier}-tier resolved_model (#{model_id}) to CC frontmatter model \"#{cc_model}\"" do
        agent = build_agent(name: "Tier #{tier} Agent", resolved_model: model_id)
        stub_syncable([ agent ])

        service.sync!

        expect(frontmatter_of(content_for(agent))["model"]).to eq(cc_model)
      end
    end

    it "maps frontier UNCONDITIONALLY to fable even when the platform Fable gate is OFF " \
       "(campaign 019f2163 inc5 directive — CC-side Fable rides the CC entitlement, " \
       "independent of Ai::FableRouting)" do
      allow(Ai::FableRouting).to receive(:enabled_for?).and_return(false)
      allow(Ai::FableRouting).to receive(:fable_model?).and_call_original

      agent = build_agent(name: "Frontier Agent", resolved_model: "claude-fable-5")
      stub_syncable([ agent ])

      service.sync!

      expect(frontmatter_of(content_for(agent))["model"]).to eq("fable")
      expect(Ai::FableRouting).not_to have_received(:enabled_for?)
    end
  end

  describe "when-to-spawn description guidance" do
    it "articulates when to spawn vs a cheaper agent for reasoning-tier" do
      agent = build_agent(name: "Reasoner", resolved_model: "claude-opus-4-8")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to include("REASONING-tier")
      expect(description).to include("prefer a cheaper agent")
    end

    it "articulates when to spawn vs a cheaper agent, more strictly, for frontier-tier" do
      agent = build_agent(name: "Frontiersman", resolved_model: "claude-fable-5")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to include("FRONTIER-tier")
      expect(description).to include("exception, not the default")
    end

    it "does not add spawn-threshold guidance for light/standard tiers" do
      agent = build_agent(name: "Light Helper", resolved_model: "claude-haiku-4-5-20251001")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to eq(agent.description)
      expect(description).not_to include("-tier (")
    end
  end

  describe "body shape" do
    it "bootstraps via the correct agent id, references get_agent, with no duplicated prompt content" do
      agent = build_agent(name: "Bootstrapped Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("mcp__powernode__platform_get_agent")
      expect(content).to include(%(agent_id: "#{agent.id}"))
      expect(content).to include("source of truth")
    end

    it "references get_skill_context with attached skill slugs when the agent has active skills" do
      agent = build_agent(name: "Skilled Agent", resolved_model: "claude-sonnet-4-6",
                           skills: %w[skill-alpha skill-beta])
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("mcp__powernode__platform_get_skill_context")
      expect(content).to include(%(agent_id: "#{agent.id}"))
      expect(content).to include("skill-alpha")
      expect(content).to include("skill-beta")
    end

    it "omits the get_skill_context step when the agent has no active skills" do
      agent = build_agent(name: "Skill-less Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).not_to include("mcp__powernode__platform_get_skill_context")
    end

    it "ignores an inactive skill attachment (not listed, get_skill_context step omitted)" do
      agent = build_agent(name: "Half-Skilled Agent", resolved_model: "claude-sonnet-4-6")
      skill = create(:ai_skill, account: account, slug: "skill-gamma", status: "active")
      create(:ai_agent_skill, agent: agent, skill: skill, is_active: false)
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).not_to include("skill-gamma")
      expect(content).not_to include("mcp__powernode__platform_get_skill_context")
    end

    it "carries the state-why-frontier-is-needed governance line ONLY in fable bodies" do
      fable_agent = build_agent(name: "Fable Agent", resolved_model: "claude-fable-5")
      sonnet_agent = build_agent(name: "Sonnet Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ fable_agent, sonnet_agent ])

      service.sync!

      fable_content = content_for(fable_agent)
      sonnet_content = content_for(sonnet_agent)

      expect(fable_content).to include("state in one sentence why frontier capability is required")
      expect(fable_content).to include("do not refuse")
      expect(sonnet_content).not_to include("state in one sentence why frontier capability is required")
    end
  end

  describe "file hygiene" do
    it "prefixes the body with the generated-file header" do
      agent = build_agent(name: "Headered Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).to include(
        "<!-- generated by claude:sync_agents — do not edit; regenerate instead -->"
      )
    end
  end

  describe "idempotency" do
    it "writes zero files on a second run over unchanged agents" do
      agent = build_agent(name: "Stable Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      first = service.sync!
      expect(first.written).to eq([ agent.slug ])
      expect(first.unchanged).to eq([])

      second = service.sync!
      expect(second.written).to eq([])
      expect(second.unchanged).to eq([ agent.slug ])
    end

    it "rewrites only the file whose content actually changed" do
      stable = build_agent(name: "Stable Agent", resolved_model: "claude-sonnet-4-6")
      changing = build_agent(name: "Changing Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ stable, changing ])
      service.sync!

      allow(changing).to receive(:description).and_return("A brand new description.")
      second = service.sync!

      expect(second.written).to eq([ changing.slug ])
      expect(second.unchanged).to eq([ stable.slug ])
    end
  end

  describe "stale cleanup" do
    it "removes a generated-header file for an agent no longer syncable" do
      agent = build_agent(name: "Going Away", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])
      service.sync!
      expect(File.exist?(path_for(agent))).to be true

      stub_syncable([])
      result = service.sync!

      expect(File.exist?(path_for(agent))).to be false
      expect(result.removed).to eq([ agent.slug ])
    end

    it "never deletes a file without the generated header" do
      hand_authored = File.join(target_dir, "hand-authored.md")
      File.write(hand_authored, "---\nname: hand-authored\ndescription: manual\nmodel: sonnet\n---\n\nHand-written.\n")
      stub_syncable([])

      service.sync!

      expect(File.exist?(hand_authored)).to be true
    end
  end
end
