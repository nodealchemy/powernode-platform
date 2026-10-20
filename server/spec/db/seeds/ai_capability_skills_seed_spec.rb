# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds/ai_capability_skills_seed.rb", type: :seed do
  let(:data_dir) { Rails.root.join("db", "seeds", "capability_skills") }

  def run_seed!
    stub_const("Powernode::Seeds", Module.new do
      def self.baseline? = true
      def self.demo? = false
    end)
    load Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb")
  end

  def capability_rows
    Ai::Skill.global.where("metadata ? 'capability'").where("metadata->>'owner_repo' = ?", "core").order(:slug)
  end

  def snapshot
    {
      skills: capability_rows.map { |s| s.attributes.except("updated_at", "created_at") },
      nodes: Ai::KnowledgeGraphNode.where(ai_skill_id: capability_rows.select(:id)).count,
      edges: Ai::KnowledgeGraphEdge.where(account_id: account.id, relation_type: %w[requires composes refines]).count,
      compositions: Ai::SkillComposition.where(composite_skill_id: capability_rows.select(:id)).count
    }
  end

  let!(:account) { create(:account) }
  let(:entries) { Ai::Skills::CapabilitySeeder.load_entries(data_dir) }

  describe "a fresh seed" do
    before { run_seed! }

    it "writes every authored core capability skill as a global, contract-conforming row" do
      expect(capability_rows.pluck(:slug)).to match_array(entries.map { |e| e["slug"] })
      capability_rows.each do |skill|
        expect(skill).to be_valid, -> { "#{skill.slug}: #{skill.errors.full_messages.join('; ')}" }
        expect(skill.account_id).to be_nil
        expect(skill.source_key).to eq(skill.slug)
        expect(skill.metadata["owner_repo"]).to eq("core")
      end
    end

    it "is idempotent: a second run leaves the same rows, nodes, edges and compositions" do
      before_state = snapshot
      run_seed!
      expect(snapshot).to eq(before_state)
    end

    it "embeds each skill's triggers together with its name and description" do
      skill = capability_rows.first
      text = Ai::SkillGraph::BridgeService.embedding_text_for(skill)
      expect(text).to include(skill.name, skill.description)
      expect(text).to include(skill.metadata.dig("triggers", "use_when").first)
      expect(text).to include(skill.metadata.dig("triggers", "keywords").first)
      skill.metadata.dig("triggers", "not_for").each { |boundary| expect(text).not_to include(boundary) }
    end

    it "projects each skill into the account's knowledge graph with its relation edges" do
      expect(Ai::KnowledgeGraphNode.where(account_id: account.id, ai_skill_id: capability_rows.select(:id)).count).to eq(capability_rows.count)

      refining = capability_rows.find { |s| Array(s.metadata.dig("relations", "refines")).any? }
      skip "no core skill declares a refinement" unless refining
      parent = Ai::Skill.global.find_by(slug: refining.metadata.dig("relations", "refines").first)
      edge = Ai::KnowledgeGraphEdge.find_by(account_id: account.id, relation_type: "refines",
                                            source_node_id: refining.knowledge_graph_node_for(account.id).id)
      expect(edge&.target_node&.ai_skill_id).to eq(parent.id)
    end

    it "names only registered platform tools as verbs" do
      registered = Ai::Tools::PlatformApiToolRegistry.all_tools
      capability_rows.each do |skill|
        missing = Array(skill.metadata.dig("manifest", "verbs")).reject { |v| registered.key?(v) }
        expect(missing).to be_empty, "#{skill.slug} names unregistered verbs #{missing.join(', ')}"
      end
    end

    it "names no extension verb anywhere in a core seed (purity)" do
      prefixes = Powernode::ExtensionRegistry.slugs.map { |s| "#{s.to_s.tr('-', '_')}_" }
      ext_verbs = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.select { |k| k.start_with?(*prefixes) }.to_set
      capability_rows.each do |skill|
        words = [ skill.system_prompt, skill.description, *Array(skill.metadata.dig("manifest", "verbs")) ].join(" ").scan(/[a-z0-9_]+/)
        expect(words.select { |w| ext_verbs.include?(w) }).to be_empty, "#{skill.slug} names an extension verb"
      end
    end
  end

  describe "failing loudly" do
    after { Ai::Skills::CapabilitySeeder.reset_failures! }

    it "prints the gate's embedding space in the seed summary" do
      expect { run_seed! }.to output(/Core capability skills: .*gate embedder: \S+/).to_stdout
    end

    it "records a rejected batch, prints a marked error and re-raises; db:seed's banner then reports it" do
      Ai::Skills::CapabilitySeeder.reset_failures!
      bad = entries.first.deep_dup.merge("description" => "Not a trigger sentence.")
      allow(Ai::Skills::CapabilitySeeder).to receive(:load_entries).and_return([ bad, *entries.drop(1) ])

      expect { run_seed! }.to raise_error(Ai::Skills::SeedGate::GateError)
                          .and output(/CORE CAPABILITY SKILL SEED FAILED/).to_stdout
      expect(capability_rows.count).to eq(0)

      io = StringIO.new
      expect(Ai::Skills::CapabilitySeeder.report_failures!(io: io).map { |f| f[:owner_repo] }).to eq(%w[core])
      expect(io.string).to include("CAPABILITY SKILL SEED FAILED")
    end
  end

  describe "the gate" do
    let(:lexical_gate) { Ai::Skills::SeedGate.new(owner_repo: "core", embedder: :lexical) }
    let(:seeder) { Ai::Skills::CapabilitySeeder.new(owner_repo: "core", gate: lexical_gate) }

    it "fails the whole batch, writing nothing, when one skill does not conform" do
      bad = entries.first.deep_dup.merge("description" => "Not a trigger sentence.")
      expect { seeder.seed!([ bad, *entries.drop(1) ]) }.to raise_error(Ai::Skills::SeedGate::GateError)
      expect(capability_rows.count).to eq(0)
    end

    it "fails the seed on a duplicate skill" do
      original = entries.first
      copy = original.deep_dup.merge("slug" => "#{original['slug']}-copy", "capability" => "#{original['capability']}-copy",
                                     "name" => "#{original['name']} Copy")
      expect { seeder.seed!([ original, copy ]) }.to raise_error(Ai::Skills::SeedGate::GateError, /duplicates/)
      expect(capability_rows.count).to eq(0)
    end

    it "passes the authored batch on the lexical proxy (no unnamed overlaps)" do
      expect { seeder.seed!(entries) }.not_to raise_error
    end
  end
end
