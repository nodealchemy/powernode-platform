# frozen_string_literal: true

require "rails_helper"

# PRE-3: regenerating the Claude Code skeletons is a pure function of the roster, so
# nothing that moves on the platform (a skill, a trigger, an agent's charter, a
# seeded agent row, an assembly) changes a committed byte and no Claude Code restart
# or committed diff follows a platform edit. This runs the REAL sync (rails
# claude:sync_agents' service) before and after such edits and compares every file
# with the committed .claude/agents/powernode.
RSpec.describe "skeleton regeneration invariance" do
  let(:committed_dir) { Rails.root.join("..", ".claude", "agents", "powernode").cleanpath }
  let(:out) { Dir.mktmpdir("skeletons") }
  let!(:account) { create(:account) }

  after { FileUtils.remove_entry(out) }

  def regenerate = Ai::ClaudeExport::AgentSkeletonSync.new(target_dir: out).sync!

  def files(dir) = Dir[File.join(dir, "*.md")].sort.to_h { |path| [ File.basename(path), File.read(path) ] }

  it "reproduces the committed files byte for byte" do
    result = regenerate

    expect(result.total).to eq(Ai::Agents::CanonicalRoster.slugs.size)
    expect(files(out)).to eq(files(committed_dir))
  end

  it "is unchanged after skills are seeded, edited and archived, agents are seeded and edited, and an assembly is made" do
    baseline = (regenerate && files(out))

    use_recorded_skill_embeddings!
    seed_with_baseline!(Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb"), *extension_capability_seed_paths)
    seed_with_baseline!(Rails.root.join("db", "seeds", "ai_canonical_agents_seed.rb"))
    Ai::Skill.global.limit(5).each do |skill|
      skill.update_columns(system_prompt: "## Procedure\n1. edited after the export", description: "Use when edited.", status: "archived")
    end
    Ai::Agent.global.where(slug: Ai::Agents::CanonicalRoster.slugs).find_each do |agent|
      agent.update!(system_prompt: "an operator's new charter", description: "Something else entirely.", status: "active")
    end
    Ai::Assembly::Service.new(account: account).call(task: "Work a dev-improve task that adds a migration and a spec", agent_slug: "platform-engineer")

    result = regenerate

    expect(files(out)).to eq(baseline)
    expect(result.written).to be_empty
    expect(result.removed).to be_empty
  end

  it "rewrites nothing on a second sync (mtime and all)" do
    regenerate
    before = Dir[File.join(out, "*.md")].to_h { |f| [ f, File.mtime(f) ] }

    result = regenerate

    expect(result.written).to be_empty
    expect(Dir[File.join(out, "*.md")].to_h { |f| [ f, File.mtime(f) ] }).to eq(before)
  end
end
