# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::CapabilitySeeder do
  let!(:account) { create(:account) }
  let(:orthogonal) do
    ->(text) { Array.new(64, 0.0).tap { |v| v[Zlib.crc32(text.split(" ").first.to_s) % 64] = 1.0 } }
  end

  def raw(slug, **overrides)
    normalized = conforming_capability_entry(slug: slug).tap { |e| e["name"] = slug }
    meta = normalized["metadata"]
    normalized.except("metadata").merge(meta.slice("domain", "capability", "triggers", "manifest", "hints", "relations", "evals")).merge(overrides.transform_keys(&:to_s))
  end

  def seed!(*entries)
    described_class.new(owner_repo: "core", embedder: orthogonal).seed!(entries)
  end

  def row(slug) = Ai::Skill.global.find_by(slug: slug)

  describe "re-seeding never fights the operator" do
    before { seed!(raw("alpha-skill")) }

    it "creates the row active, enabled, at 1.0.0, with the seed digest" do
      skill = row("alpha-skill")
      expect([ skill.status, skill.is_enabled, skill.version ]).to eq([ "active", true, "1.0.0" ])
      expect(skill.metadata["seed_digest"]).to be_present
    end

    it "reports an identical re-seed as unchanged and writes nothing" do
      before_attrs = row("alpha-skill").attributes
      result = seed!(raw("alpha-skill"))
      expect(result.unchanged).to eq([ "alpha-skill" ])
      expect(row("alpha-skill").attributes).to eq(before_attrs)
    end

    it "leaves an archived row archived, and its content alone" do
      row("alpha-skill").update_columns(status: "archived")
      result = seed!(raw("alpha-skill", description: "Use when the seed changed its mind."))
      expect(result.skipped_inactive).to eq([ "alpha-skill" ])
      expect(row("alpha-skill").status).to eq("archived")
      expect(row("alpha-skill").description).not_to include("changed its mind")
    end

    it "keeps an operator's is_enabled toggle" do
      row("alpha-skill").update!(is_enabled: false)
      seed!(raw("alpha-skill"))
      expect(row("alpha-skill").is_enabled).to be(false)
    end

    it "keeps an edited prompt (an operator edit or a prompt fold-in) and says so" do
      edited = "#{row('alpha-skill').system_prompt}\n- operator note: check the staging queue first"
      row("alpha-skill").update!(system_prompt: edited)
      result = seed!(raw("alpha-skill", description: "Use when the seed changed its mind."))
      expect(result.skipped_modified).to eq([ "alpha-skill" ])
      expect(row("alpha-skill").system_prompt).to eq(edited)
      expect(row("alpha-skill").description).not_to include("changed its mind")
    end

    it "gives an unedited row the new seed content, keeping its version" do
      result = seed!(raw("alpha-skill", description: "Use when the seed changed its mind."))
      expect(result.updated).to eq([ "alpha-skill" ])
      expect(row("alpha-skill").description).to eq("Use when the seed changed its mind.")
      expect(row("alpha-skill").version).to eq("1.0.0")

      expect(seed!(raw("alpha-skill", description: "Use when the seed changed its mind.")).unchanged).to eq([ "alpha-skill" ])
    end
  end

  describe "post-write failures are counted, never lost" do
    it "counts a knowledge-graph node that failed to sync" do
      allow_any_instance_of(Ai::SkillGraph::BridgeService).to receive(:sync_skill).and_return(nil)
      result = seed!(raw("alpha-skill"))
      expect(result.graph_failures).to include(a_string_matching(/account #{account.id}: alpha-skill node sync failed/))
    end

    it "counts a composition that failed to record" do
      allow(Ai::SkillComposition).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      result = seed!(raw("beta-skill"), raw("alpha-skill", relations: { "composes" => %w[beta-skill] }))
      expect(result.graph_failures).to include(a_string_matching(/\Acompositions: /))
      expect(row("alpha-skill")).to be_present
    end

    it "records composites in the composition table in order" do
      seed!(raw("beta-skill"), raw("gamma-skill"), raw("alpha-skill", relations: { "composes" => %w[gamma-skill beta-skill] }))
      components = Ai::SkillComposition.for_composite(row("alpha-skill").id).in_order.map { |c| c.component_skill.slug }
      expect(components).to eq(%w[gamma-skill beta-skill])
    end
  end

  describe "relations to an operator-archived target" do
    it "seeds the batch, skips the relation and reports it in the summary" do
      seed!(raw("beta-skill"))
      row("beta-skill").update_columns(status: "archived")
      result = seed!(raw("alpha-skill", relations: { "requires" => %w[beta-skill] }))

      expect(row("alpha-skill")).to be_present
      expect(result.warnings).to include(a_string_matching(/requires beta-skill skipped/))
      expect(result.summary).to include("1 warning")
      expect(Ai::KnowledgeGraphEdge.where(account_id: account.id, relation_type: "requires")).to be_empty
    end
  end

  describe "accounts created after the seed" do
    it "get the relation edges, not only the nodes, from the account graph sync" do
      allow(Account).to receive(:find_each) # the seed sees no account yet
      seed!(raw("beta-skill"), raw("alpha-skill", relations: { "requires" => %w[beta-skill] }))
      later = account

      Ai::SkillGraph::BridgeService.new(later).sync_all_skills
      source = row("alpha-skill").knowledge_graph_node_for(later.id)
      target = row("beta-skill").knowledge_graph_node_for(later.id)
      expect(Ai::KnowledgeGraphEdge.where(account_id: later.id, source_node_id: source&.id, target_node_id: target&.id, relation_type: "requires")).to exist
    end
  end

  describe "BridgeService#sync_capability_relations" do
    it "records a failure, rather than skipping silently, for a relation whose target is not seeded" do
      skill = seed!(raw("alpha-skill")).skills.first
      skill.update_columns(metadata: skill.metadata.merge("relations" => { "requires" => %w[ghost-skill] }))
      failures = Ai::SkillGraph::BridgeService.new(account).sync_capability_relations([ skill.reload ])
      expect(failures).to include(a_string_matching(/alpha-skill requires ghost-skill: .*not seeded/))
    end

    it "creates each declared edge once, however often it runs" do
      seed!(raw("beta-skill"), raw("alpha-skill", relations: { "requires" => %w[beta-skill] }))
      bridge = Ai::SkillGraph::BridgeService.new(account)
      expect { bridge.sync_capability_relations([ row("alpha-skill") ]) }
        .not_to change { Ai::KnowledgeGraphEdge.where(account_id: account.id, relation_type: "requires").count }.from(1)
    end
  end

  describe ".content_digest" do
    it "distinguishes false from nil (a boolean hint flipped to false is a content change)" do
      base = { name: "a", description: "d", category: "c", tags: [], system_prompt: "p" }
      with_false = described_class.content_digest(**base, metadata: { "hints" => { "tool_heavy" => false } })
      with_nil = described_class.content_digest(**base, metadata: { "hints" => { "tool_heavy" => nil } })
      expect(with_false).not_to eq(with_nil)
    end
  end

  describe "failure registry" do
    after { described_class.reset_failures! }

    it "prints a marked banner for every recorded failure" do
      described_class.reset_failures!
      described_class.record_failure!("core", Ai::Skills::SeedGate::GateError.new("alpha-skill: duplicates beta-skill"))
      io = StringIO.new
      failures = described_class.report_failures!(io: io)
      expect(failures.map { |f| f[:owner_repo] }).to eq(%w[core])
      expect(io.string).to include("CAPABILITY SKILL SEED FAILED", "core", "duplicates beta-skill")
    end
  end
end
