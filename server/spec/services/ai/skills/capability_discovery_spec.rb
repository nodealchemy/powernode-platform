# frozen_string_literal: true

require "rails_helper"

# Discovery evals for the CORE capability skills, with every loaded
# extension's capability batch present.
#
#   ranking          — REAL provider embeddings replayed from the recorded
#                      fixture (CapabilityDiscoveryHelpers#use_recorded_skill_embeddings!);
#                      strict per-eval checks.
#   lexical proxy    — the deterministic offline embedder with the legacy
#                      skills competing: structural checks only.
#   production cut-off — the real SEED_DISTANCE_THRESHOLD, not lifted.
#
# Production numbers (real threshold, legacy competition): `rails skills:eval:discovery`.
RSpec.describe "core capability skill discovery", type: :service do
  let!(:account) { create(:account) }
  let(:entries) { Ai::Skills::CapabilitySeeder.load_entries(Rails.root.join("db", "seeds", "capability_skills")) }
  let(:engineer_ceiling) { Ai::Skills::Contract::CORE_DOMAINS - %w[front-door] }
  let(:platform_dev) { platform_dev_slugs(entries) }
  let(:capability_seeds) { [ Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb"), *extension_capability_seed_paths ] }

  def top(task, **facets)
    discovered_slugs(account, task, **facets).first(CapabilityDiscoveryHelpers::TOP_K)
  end

  it "has a recorded real embedding for every loaded owner's skill texts and tasks (re-record after editing a skill)" do
    Ai::Skills::CapabilitySeeder.owner_roots.each do |owner, root|
      file = Ai::Skills::RecordedEmbeddings.fixture_dir(root).join("vectors.json")
      recorded = file.exist? ? JSON.parse(file.read)["vectors"] : {}
      stale = Ai::Skills::RecordedEmbeddings.corpus_for(owner, root).reject { |text| recorded.key?(Ai::Skills::RecordedEmbeddings.key(text)) }
      expect(stale).to be_empty, "#{owner}: #{stale.size} text(s) not recorded; run rails \"skills:eval:record_embeddings[,#{owner}]\":\n#{stale.first(5).join("\n")}"
    end
  end

  # Each owner keeps its own eval fixtures (recorded vectors, extra tasks,
  # miss ledger) beside its own specs; core's never name another owner's skill.
  it "keeps core's eval fixtures free of other owners' skills" do
    core_slugs = entries.map { |e| e["slug"] }
    ledger = YAML.safe_load_file(Rails.root.join("spec", "fixtures", "skill_embeddings", "known_misses.yml")) || {}
    expect(ledger.keys.map { |k| k.split(" | ").first } - core_slugs).to be_empty
  end

  # Core's own batch only, so these results (and core's miss ledger) are the
  # same whether or not any extension is loaded. Core's evals are ALSO scored
  # with every extension batch present, in each extension's own spec.
  describe "ranking on recorded real embeddings (core batch)" do
    before do
      use_recorded_skill_embeddings!
      seed_with_baseline!(Rails.root.join("db", "seeds", "ai_capability_skills_seed.rb"))
    end

    it "puts each skill in the top 3 for its positive evals and keeps it out of the top 3 for its negatives" do
      expect_misses_within_ledger(eval_misses(account, entries), entries, owner: Ai::Skills::Contract::CORE_OWNER)
    end

    {
      "Work a dev-improve task that adds a migration and a spec" => %w[dev-loop-execution rails-backend-conventions test-authoring],
      "Review this campaign increment against its acceptance criteria" => %w[acceptance-criteria-review campaign-increment-protocol],
      "Help me onboard: I want to set up Powernode for my team" => %w[front-door-triage provisioning-brief-capture]
    }.each do |task, owners|
      it "v1: returns an owning skill for #{task.inspect}" do
        expect(top(task) & owners).not_to be_empty, "got #{top(task).inspect}"
      end
    end

    describe "work for user projects, not this platform's repository" do
      {
        "Add a contact form to a customer's static website" => "website-development",
        "Set up CI for a customer's Node app" => "ci-pipeline-setup",
        "Speed up a customer's Jest test suite by running it in parallel" => "parallel-testing",
        "Give each feature of a customer's Rails app its own worktree" => "worktree-lifecycle",
        "Have three agents work on separate features of a customer's app at the same time" => "concurrent-task-orchestration"
      }.each do |task, owner|
        it "selects #{owner} and no platform-dev skill anywhere in the top 3 for #{task.inspect}" do
          ranked = top(task)
          expect(ranked).to include(owner)
          expect(ranked & platform_dev).to be_empty, "got #{ranked.inspect}"
        end
      end
    end

    describe "the platform's own repository" do
      {
        "Run the dev-loop with 4 tasks in parallel" => "powernode-concurrent-tasks",
        "Run the full suite fast" => "powernode-parallel-rspec",
        "Clean up merged worktrees" => "powernode-worktree-lifecycle"
      }.each do |task, owner|
        it "selects the #{owner} refinement over its generic parent for #{task.inspect}" do
          ranked = top(task, project_kind: "powernode-platform")
          expect(ranked).to include(owner)
          parent = entries.find { |e| e["slug"] == owner }.dig("relations", "refines")&.first
          expect(ranked).not_to include(parent) if parent
        end
      end
    end

    it "gives the engineer the deployment hand-off, inside its domain ceiling, for \"deploy my app\"" do
      expect(top("Deploy my app", domains: engineer_ceiling).first).to eq("deployment-handoff")
    end
  end

  describe "lexical proxy, legacy skills competing" do
    before do
      use_lexical_skill_embeddings!
      seed_with_baseline!(Rails.root.join("db", "seeds", "ai_skills_seed.rb"), *extension_legacy_skill_seed_paths, *capability_seeds)
    end

    it "still returns a skill for a marketing task (the legacy skill until its re-authoring)" do
      expect(discovered_slugs(account, "Plan a marketing campaign for our product launch")).not_to be_empty
    end

    it "returns a skill within the default token budget" do
      expect(discovered_slugs(account, "Work a dev-improve task that adds a migration and a spec", token_budget: 2_000)).not_to be_empty
    end

    it "drops platform-dev skills entirely when a user project's kind is given" do
      ranked = discovered_slugs(account, "Run the full test suite fast in parallel", project_kind: "web-app")
      expect(ranked & platform_dev).to be_empty
      expect(ranked).to include("parallel-testing")
    end

    it "never lists a refinement together with its parent" do
      ranked = discovered_slugs(account, "Run the full test suite fast in parallel")
      expect(ranked & %w[parallel-testing powernode-parallel-rspec]).to be_one
    end

    it "keeps the refinement, not the parent, for the platform's own repository" do
      ranked = top("Run the full test suite fast in parallel", project_kind: "powernode-platform")
      expect(ranked).to include("powernode-parallel-rspec")
      expect(ranked).not_to include("parallel-testing")
    end
  end

  # The production seed cut-off (cosine distance <= SEED_DISTANCE_THRESHOLD),
  # NOT lifted: a task worded like a skill's own trigger clears it and lands on
  # that skill; an unrelated task returns nothing rather than a weak guess.
  describe "at the production seed cut-off" do
    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate) { |_svc, text, **| Ai::Skills::LexicalEmbedder.embed(text) }
      seed_with_baseline!(*capability_seeds)
    end

    it "keeps the production threshold" do
      expect(Ai::SkillGraph::TraversalService::SEED_DISTANCE_THRESHOLD).to eq(0.6)
    end

    it "clears the cut-off for a task worded like the skill's own triggers" do
      skill = Ai::Skill.global.find_by(slug: "release-promotion")
      task = [ skill.name, skill.description, *skill.metadata.dig("triggers", "keywords") ].join(" ")
      expect(discovered_slugs(account, task).first).to eq("release-promotion")
    end

    it "returns nothing for a task no skill owns" do
      expect(discovered_slugs(account, "bake a chocolate cake with raspberries for grandma")).to be_empty
    end
  end
end
