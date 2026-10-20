# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::SeedGate do
  def entry(slug, **opts)
    conforming_capability_entry(slug: slug, **opts).tap { |e| e["name"] = slug }
  end

  # One orthogonal axis per skill (keyed on the leading name = slug), so only the
  # similarity examples below see any overlap at all.
  let(:orthogonal) do
    lambda do |text|
      Array.new(64, 0.0).tap { |v| v[Zlib.crc32(text.split(" ").first.to_s) % 64] = 1.0 }
    end
  end
  let(:gate) { described_class.new(owner_repo: "core", embedder: orthogonal) }

  it "passes a conforming batch" do
    expect(gate.check!([ entry("alpha-skill"), entry("beta-skill") ])).to be(true)
  end

  it "rejects a batch with a non-conforming skill" do
    bad = entry("alpha-skill").tap { |e| e["description"] = "Handles alpha." }
    expect { gate.check!([ bad ]) }.to raise_error(described_class::GateError, /must start with "Use when"/)
  end

  describe "similarity within a domain (ConflictDetectionService bands)" do
    # cos(a, b) = a0*b0 + a1*b1; one skill at [1, 0] and the other at [s, sqrt(1-s^2)] gives cos = s.
    def gate_for(similarity)
      embed = lambda do |text|
        text.start_with?("alpha-skill") ? [ 1.0, 0.0 ] : [ similarity, Math.sqrt(1 - (similarity**2)) ]
      end
      described_class.new(owner_repo: "core", embedder: embed)
    end

    it "fails the seed on a duplicate (>= 0.92)" do
      expect { gate_for(0.95).check!([ entry("alpha-skill"), entry("beta-skill") ]) }
        .to raise_error(described_class::GateError, /alpha-skill: duplicates beta-skill/)
    end

    it "requires not_for to name the sibling on an overlap (0.7-0.92)" do
      expect { gate_for(0.8).check!([ entry("alpha-skill"), entry("beta-skill") ]) }
        .to raise_error(described_class::GateError, /alpha-skill: overlaps beta-skill .*not_for must name beta-skill/)
    end

    it "passes an overlap when each side names the other in not_for" do
      a = entry("alpha-skill").tap { |e| e["metadata"]["triggers"]["not_for"] = [ "beta work — use beta-skill" ] }
      b = entry("beta-skill").tap { |e| e["metadata"]["triggers"]["not_for"] = [ "alpha work — use alpha-skill" ] }
      expect(gate_for(0.8).check!([ a, b ])).to be(true)
    end

    it "does not compare skills across domains" do
      b = entry("beta-skill", domain: "review")
      expect(gate_for(0.99).check!([ entry("alpha-skill"), b ])).to be(true)
    end

    it "compares against an already-seeded sibling in the same domain" do
      Ai::Skills::CapabilitySeeder.new(owner_repo: "core", gate: described_class.new(owner_repo: "core", embedder: orthogonal))
                                  .seed!([ raw_entry(entry("beta-skill")) ])
      expect { gate_for(0.95).check!([ entry("alpha-skill") ]) }
        .to raise_error(described_class::GateError, /alpha-skill: duplicates beta-skill/)
    end
  end

  describe "identity" do
    it "rejects two owners of one capability in a batch" do
      b = entry("beta-skill").tap { |e| e["metadata"]["capability"] = "alpha-skill" }
      expect { gate.check!([ entry("alpha-skill"), b ]) }.to raise_error(described_class::GateError, /capability alpha-skill has more than one owner/)
    end

    it "rejects a verb that is not a registered platform tool" do
      e = entry("alpha-skill").tap { |x| x["metadata"]["manifest"]["verbs"] = %w[no_such_verb_anywhere] }
      expect { gate.check!([ e ]) }.to raise_error(described_class::GateError, /no_such_verb_anywhere is not a registered platform tool/)
    end

    it "rejects a relation to a skill that is not seeded" do
      e = entry("alpha-skill").tap { |x| x["metadata"]["relations"] = { "requires" => %w[ghost-skill] } }
      expect { gate.check!([ e ]) }.to raise_error(described_class::GateError, /ghost-skill is not a seeded capability skill/)
    end

    it "rejects an owner_repo that does not match the seeding repo" do
      e = entry("alpha-skill", owner_repo: "core")
      expect { described_class.new(owner_repo: "extensions/other", embedder: orthogonal).check!([ e ]) }
        .to raise_error(described_class::GateError, /does not match the seeding repo/)
    end
  end

  describe "slug collisions (never adopt a row the seed does not own)" do
    it "rejects a slug taken by a legacy global skill" do
      create(:ai_skill, :global, :system_skill, slug: "alpha-skill", name: "Legacy Alpha", metadata: { "domain" => "platform" })
      expect { gate.check!([ entry("alpha-skill") ]) }.to raise_error(described_class::GateError, /taken by a legacy global skill/)
    end

    it "rejects a slug owned by another owner's global capability row" do
      other = entry("alpha-skill").tap { |e| e["metadata"]["owner_repo"] = "extensions/other" }
      Ai::Skill.new(other.slice("slug", "name", "category", "description", "tags", "system_prompt", "metadata")
                         .merge(account_id: nil, is_system: true, status: "active")).save!(validate: false)
      expect { gate.check!([ entry("alpha-skill") ]) }.to raise_error(described_class::GateError, /owned by "extensions\/other"/)
    end

    # An account's override of a global skill keeps the global slug (clone-on-
    # evolve); the seed writes only the global row, so the override is not a
    # collision. A tenant's own row that merely shares the slug (no global
    # origin) is reported — it shadows the global in that account — but does
    # not block the seed.
    it "does not let an account override of a seeded skill block the re-seed" do
      Ai::Skills::CapabilitySeeder.new(owner_repo: "core", gate: gate).seed!([ raw_entry(entry("alpha-skill")) ])
      global = Ai::Skill.global.find_by(slug: "alpha-skill")
      override = global.clone_to_account(create(:account))
      override.slug = global.slug
      override.name = global.name
      override.save!(validate: false)

      reseed_gate = described_class.new(owner_repo: "core", embedder: orthogonal)
      expect(reseed_gate.check!([ entry("alpha-skill") ])).to be(true)
      expect(reseed_gate.warnings([ entry("alpha-skill") ])).to be_empty
    end

    it "warns about, but does not reject, a tenant row that shares the slug with no global origin" do
      create(:ai_skill, account: create(:account), slug: "alpha-skill", name: "Tenant Alpha")
      expect(gate.check!([ entry("alpha-skill") ])).to be(true)
      expect(gate.warnings([ entry("alpha-skill") ])).to include(a_string_matching(/account-scoped row.*no global origin and shadow it/))
    end

    it "accepts the seed's own global row on a re-seed" do
      Ai::Skills::CapabilitySeeder.new(owner_repo: "core", gate: gate).seed!([ raw_entry(entry("alpha-skill")) ])
      expect(described_class.new(owner_repo: "core", embedder: orthogonal).check!([ entry("alpha-skill") ])).to be(true)
    end
  end

  describe "relations to an operator-archived target" do
    it "skips the relation with a warning instead of rejecting the batch" do
      Ai::Skills::CapabilitySeeder.new(owner_repo: "core", gate: gate).seed!([ raw_entry(entry("beta-skill")) ])
      Ai::Skill.global.find_by(slug: "beta-skill").update_columns(status: "archived")
      alpha = entry("alpha-skill").tap { |x| x["metadata"]["relations"] = { "requires" => %w[beta-skill] } }

      expect(gate.check!([ alpha ])).to be(true)
      expect(gate.warnings([ alpha ])).to include(a_string_matching(/requires beta-skill skipped: target is archived/))
    end

    it "still rejects a target that was never seeded" do
      alpha = entry("alpha-skill").tap { |x| x["metadata"]["relations"] = { "requires" => %w[never-seeded] } }
      expect { gate.check!([ alpha ]) }.to raise_error(described_class::GateError, /never-seeded is not a seeded capability skill/)
    end
  end

  describe "embedding modes" do
    it "fails in :provider mode when the provider cannot embed every text, instead of falling back" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil).and_return(nil)
      expect { described_class.new(owner_repo: "core", embedder: :provider).check!([ entry("alpha-skill"), entry("beta-skill") ]) }
        .to raise_error(Ai::Skills::SkillEmbedder::EmbeddingUnavailable)
    end

    it "falls back to lexical for every text in :auto mode, and says so" do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_or_nil).and_return(nil)
      auto = described_class.new(owner_repo: "core", embedder: :auto)
      auto.violations([ entry("alpha-skill"), entry("beta-skill", domain: "review") ])
      expect(auto.embedder_mode_used).to eq("lexical (provider unavailable)")
    end

    it "rejects an unknown mode" do
      expect { described_class.new(owner_repo: "core", embedder: :magic) }.to raise_error(ArgumentError, /provider, lexical, auto/)
    end
  end

  describe "#similarity_report (the dry run)" do
    it "lists same-domain pairs at or above 0.6 with band, margin and naming, and writes nothing" do
      embed = ->(text) { text.start_with?("alpha-skill") ? [ 1.0, 0.0 ] : [ 0.75, Math.sqrt(1 - 0.5625) ] }
      report_gate = described_class.new(owner_repo: "core", embedder: embed)
      expect do
        pair = report_gate.similarity_report([ entry("alpha-skill"), entry("beta-skill") ]).sole
        expect(pair).to include(a: "alpha-skill", b: "beta-skill", band: "overlapping", a_names_b: false, b_names_a: false)
        expect(pair[:similarity]).to be_within(0.001).of(0.75)
        expect(pair[:margin]).to be_within(0.001).of(0.17)
      end.not_to change(Ai::Skill, :count)
    end
  end

  describe "core/extension purity" do
    # A fixture extension owner, so these run in core mode too: the gate sees
    # one more extension slug and one verb carrying its prefix.
    let(:extension_slug) { "purityfixture" }
    let(:extension_verb) { "purityfixture_do_thing" }

    before do
      tools = Ai::Tools::PlatformApiToolRegistry.all_tools.merge(extension_verb => "Object")
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_return(tools)
      allow_any_instance_of(described_class).to receive(:extension_slugs).and_wrap_original do |original, *args|
        (original.call(*args) | [ extension_slug ])
      end
    end

    around do |example|
      registry = Ai::Skills::Contract.instance_variable_get(:@registered_domains).dup
      example.run
    ensure
      Ai::Skills::Contract.instance_variable_set(:@registered_domains, registry)
    end

    it "fails a core seed whose manifest names an extension verb" do
      e = entry("alpha-skill").tap { |x| x["metadata"]["manifest"]["verbs"] = [ extension_verb ] }
      expect { gate.check!([ e ]) }.to raise_error(described_class::GateError, /names another owner's verb #{extension_verb}/)
    end

    it "fails a core seed whose prompt names an extension verb" do
      e = entry("alpha-skill").tap { |x| x["system_prompt"] += "\n- call #{extension_verb} first" }
      expect { gate.check!([ e ]) }.to raise_error(described_class::GateError, /text names another owner's verb #{extension_verb}/)
    end

    it "lets the owning extension name its own verbs" do
      Ai::Skills::Contract.register_domains(owner: "extensions/#{extension_slug}", domains: %w[purity-spec-domain])
      e = entry("alpha-skill", owner_repo: "extensions/#{extension_slug}", domain: "purity-spec-domain")
      e["metadata"]["manifest"]["verbs"] = [ extension_verb ]
      e["metadata"]["triggers"]["applies_to"] = %w[infrastructure]
      own_gate = described_class.new(owner_repo: "extensions/#{extension_slug}", embedder: orthogonal)
      expect(own_gate.check!([ e ])).to be(true)
    end

    it "fails a core skill that relates to an extension-owned skill even after an operator archived it" do
      Ai::Skills::Contract.register_domains(owner: "extensions/#{extension_slug}", domains: %w[purity-spec-domain])
      ext = entry("ext-owned-skill", owner_repo: "extensions/#{extension_slug}", domain: "purity-spec-domain")
      ext["metadata"]["triggers"]["applies_to"] = %w[infrastructure]
      Ai::Skills::CapabilitySeeder.new(owner_repo: "extensions/#{extension_slug}",
                                       gate: described_class.new(owner_repo: "extensions/#{extension_slug}", embedder: orthogonal))
                                  .seed!([ raw_entry(ext) ])
      Ai::Skill.global.find_by(slug: "ext-owned-skill").update_columns(status: "archived")

      core = entry("alpha-skill").tap { |x| x["metadata"]["relations"] = { "requires" => %w[ext-owned-skill] } }
      expect { gate.check!([ core ]) }.to raise_error(described_class::GateError, /belongs to extensions\/#{extension_slug}/)
    end

    it "fails a core skill that relates to an extension-owned skill" do
      Ai::Skills::Contract.register_domains(owner: "extensions/#{extension_slug}", domains: %w[purity-spec-domain])
      ext = entry("ext-owned-skill", owner_repo: "extensions/#{extension_slug}", domain: "purity-spec-domain")
      ext["metadata"]["triggers"]["applies_to"] = %w[infrastructure]
      Ai::Skills::CapabilitySeeder.new(owner_repo: "extensions/#{extension_slug}",
                                       gate: described_class.new(owner_repo: "extensions/#{extension_slug}", embedder: orthogonal))
                                  .seed!([ raw_entry(ext) ])

      core = entry("alpha-skill").tap { |x| x["metadata"]["relations"] = { "requires" => %w[ext-owned-skill] } }
      expect { gate.check!([ core ]) }.to raise_error(described_class::GateError, /belongs to extensions\/#{extension_slug}/)
    end
  end

  # Normalized entry → the raw YAML shape CapabilitySeeder#seed! accepts.
  def raw_entry(normalized)
    meta = normalized["metadata"]
    normalized.except("metadata").merge(meta.slice("domain", "capability", "triggers", "manifest", "hints", "relations", "evals"))
  end
end
