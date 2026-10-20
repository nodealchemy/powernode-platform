# frozen_string_literal: true

# Discovery-eval helpers for capability skills.
#
# The test-mode provider embedding is random per text, so it cannot rank. These
# helpers swap in Ai::Skills::LexicalEmbedder — a deterministic bag-of-words
# proxy — and lift the traversal's distance threshold, which is calibrated for
# the provider's (semantic) scale, not this one. What the evals then assert is
# RANKING: that a task, phrased as users phrase it, lands on the skill that owns
# it rather than a sibling.
module CapabilityDiscoveryHelpers
  TOP_K = 3

  def use_lexical_skill_embeddings!
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate) { |_svc, text, **| Ai::Skills::LexicalEmbedder.embed(text) }
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil) { |_svc, text, **| Ai::Skills::LexicalEmbedder.embed(text) }
    stub_const("Ai::SkillGraph::TraversalService::SEED_DISTANCE_THRESHOLD", 1.0)
  end

  # Replays REAL provider embeddings recorded by
  # `rails skills:eval:record_embeddings` (see Ai::Skills::RecordedEmbeddings),
  # so ranking specs see production-like similarities AT the production seed
  # cut-off. The recorded vectors are compact prefixes whose cosines track the
  # full ones within a few hundredths; the provider-backed runner
  # (`rails skills:eval:discovery`) remains the authority on exact numbers.
  def use_recorded_skill_embeddings!
    lookup = Ai::Skills::RecordedEmbeddings.lookup(Ai::Skills::RecordedEmbeddings.combined_fixture)
    # Texts outside the corpus (e.g. a graph node's own description embedding,
    # overwritten by the skill text right after) embed as nil; a TASK must be
    # recorded — #discovered_slugs checks that before ranking.
    replay = lambda do |text|
      lookup.call(text)
    rescue Ai::Skills::RecordedEmbeddings::Missing
      nil
    end
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate) { |_svc, text, **| replay.call(text) }
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil) { |_svc, text, **| replay.call(text) }
    @recorded_lookup = lookup
  end

  def seed_with_baseline!(*seed_paths)
    stub_const("Powernode::Seeds", Module.new do
      def self.baseline? = true
      def self.demo? = false
    end)
    seed_paths.each { |path| load path }
  end

  # Ranked slugs for a task. A large budget so ranking, not the prompt-size
  # budget, decides what is returned.
  def discovered_slugs(account, task, token_budget: 100_000, **facets)
    @recorded_lookup&.call(task) # raises Missing (with the re-record command) for an unrecorded task
    Ai::SkillGraph::TraversalService.new(account)
                                    .traverse(task_context: task, mode: :auto, token_budget: token_budget, **facets)[:discovered_skills]
                                    .map { |entry| entry[:slug] }
  end

  # [slug, task, expect_selected, facets] for every eval of every entry.
  def eval_cases(entries)
    entries.flat_map do |entry|
      Array(entry["evals"]).map do |ev|
        facets = ev["project_kind"] ? { project_kind: ev["project_kind"] } : {}
        [ entry["slug"], ev["task"], ev["expect_selected"], facets ]
      end
    end
  end

  # Eval misses: a positive outside the top K, or a negative inside it.
  # @return [Hash{String => String}] "slug | task" => description
  def eval_misses(account, entries)
    eval_cases(entries).each_with_object({}) do |(slug, task, expected, facets), misses|
      ranked = discovered_slugs(account, task, **facets)
      key = "#{slug} | #{task}"
      if expected && !ranked.first(TOP_K).include?(slug)
        misses[key] = "#{slug} not in top #{TOP_K} for #{task.inspect} #{facets.inspect} (got #{ranked.first(3).inspect})"
      elsif !expected && ranked.first(TOP_K).include?(slug)
        misses[key] = "#{slug} in the top #{TOP_K} for its negative eval #{task.inspect} #{facets.inspect} (got #{ranked.first(3).inspect})"
      end
    end
  end

  # A ratchet over the recorded-embedding misses, like the repo's other
  # baselines. A ledger belongs to ONE scoring run: the owner whose spec scores
  # `entries` against the batches it seeds keeps known_misses.yml beside that
  # spec (<owner root>/spec/fixtures/skill_embeddings/). Core scores its own
  # evals against its own batch only, so its ledger never depends on whether an
  # extension is loaded; an extension scores core's and its own evals with both
  # batches present, so its ledger may name core skills too. Every miss must be
  # listed (with why), every listed miss must still miss — fix one and the spec
  # asks you to delete its line — and every line must name a scored skill.
  def expect_misses_within_ledger(misses, entries, owner:)
    root = Ai::Skills::CapabilitySeeder.owner_roots.to_h.fetch(owner)
    file = Ai::Skills::RecordedEmbeddings.fixture_dir(root).join("known_misses.yml")
    ledger = file.exist? ? (YAML.safe_load_file(file) || {}) : {}
    slugs = entries.map { |e| e["slug"] }
    orphans = ledger.keys.reject { |key| slugs.include?(key.split(" | ").first) }
    unlisted = misses.reject { |key, _| ledger.key?(key) }
    fixed = ledger.keys - misses.keys - orphans
    expect(orphans).to be_empty, "#{file}: entries for skills this run does not score; delete them:\n#{orphans.join("\n")}"
    expect(unlisted.values).to be_empty, "new eval misses (fix the triggers, or list them with a reason in #{file}):\n#{unlisted.values.join("\n")}"
    expect(fixed).to be_empty, "these ledger entries no longer miss; delete them from #{file}:\n#{fixed.join("\n")}"
  end

  # Every loaded extension's capability seed file, found through the registry
  # (none in core mode), so core evals run with every batch present.
  def extension_capability_seed_paths
    Powernode::ExtensionRegistry.all.values.filter_map do |ext|
      Dir[ext[:engine].root.join("db", "seeds", "*_capability_skills_seed.rb")].first
    end
  end

  # Every loaded extension's legacy skill catalog seeds (competition until P3).
  def extension_legacy_skill_seed_paths
    Powernode::ExtensionRegistry.all.values.flat_map do |ext|
      Dir[ext[:engine].root.join("db", "seeds", "*_skills_seed.rb")].reject { |p| p.end_with?("_capability_skills_seed.rb") }.sort
    end
  end

  def platform_dev_slugs(entries)
    entries.select { |e| e["domain"] == Ai::Skills::Contract::PLATFORM_DEV_DOMAIN }.map { |e| e["slug"] }
  end
end

RSpec.configure { |config| config.include CapabilityDiscoveryHelpers }
