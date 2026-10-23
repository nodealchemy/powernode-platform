# frozen_string_literal: true

require "rails_helper"

# The canonical roster is a REGISTRY (skills-first agents, PRE-2): core declares
# its own three agents and an extension registers its agents from its engine.
# The seed, the Claude Code export and the thin loader read this and nothing
# else, so a core-mode install exports three skeletons and a system-enabled one
# four, and core never names an extension's agent.
RSpec.describe Ai::Agents::CanonicalRoster do
  let(:core_slugs) { %w[powernode-concierge platform-engineer platform-reviewer] }

  def spec_for(slug, **overrides)
    base = {
      name: slug.titleize, agent_type: "assistant", tier: "standard", description: "Does #{slug}.",
      domains: %w[knowledge], role: { code: false, shell: false, server_grant: false, read_only: false, verbs: [], duty: "Do the duty." },
      charter: "You are #{slug}.", posture: {}
    }
    base.merge(overrides)
  end

  # An isolated registry, so specs neither see nor leak an extension's entries.
  def with_registry(entries = {})
    registry = described_class::Registry.new
    entries.each { |slug, spec| registry.register(slug, spec, owner: "core") }
    allow(described_class).to receive(:registry).and_return(registry)
    registry
  end

  describe "core's declaration" do
    it "declares exactly the three core agents, owned by core" do
      core = described_class.each.select { |_slug, _spec, owner| owner == described_class::CORE_OWNER }.map(&:first)

      expect(core).to match_array(core_slugs)
    end

    it "carries no extension agent in core's own source (the registry is the only seam)" do
      source = File.read(Rails.root.join("app/services/ai/agents/canonical_roster.rb"))

      expect(source).not_to include("fleet-operator")
    end

    it "gives every core agent the full spec: tier, domain ceiling, role, charter and posture" do
      core_slugs.each do |slug|
        spec = described_class.fetch(slug)
        expect(spec.keys).to include(:name, :agent_type, :tier, :description, :domains, :role, :charter, :posture)
        expect(spec[:domains]).to all(be_a(String)).and(be_present)
        expect(spec[:role].keys - [ :shell_guard ]).to match_array(%i[code shell server_grant read_only verbs duty])
      end
    end

    it "pins the roster tiers: concierge and engineer standard, reviewer reasoning" do
      expect(core_slugs.to_h { |s| [ s, described_class.fetch(s)[:tier] ] })
        .to eq("powernode-concierge" => "standard", "platform-engineer" => "standard", "platform-reviewer" => "reasoning")
    end

    it "gives the reviewer no shell and no Edit/Write in phase 1, and says so in its charter" do
      reviewer = described_class.fetch("platform-reviewer")

      expect(reviewer[:role]).to include(code: false, shell: false)
      expect(reviewer[:role]).not_to have_key(:shell_guard)
      expect(reviewer[:charter]).to match(/no shell/i)
      expect(reviewer[:charter]).to match(/never edit, commit/i)
    end

    it "still refuses a shell role without code that names no shell_guard" do
      registry = described_class::Registry.new
      spec = described_class.fetch("platform-reviewer").merge(role: described_class.fetch("platform-reviewer")[:role].merge(shell: true))

      expect { registry.register("x-reviewer", spec, owner: "core") }.to raise_error(ArgumentError, /shell_guard/)
    end

    it "makes the reviewer read-only with an explicit verb list, and the concierge an explicit list too (no whole-server grant)" do
      expect(described_class.fetch("platform-reviewer")[:role]).to include(read_only: true, server_grant: false)
      expect(described_class.fetch("platform-reviewer")[:role][:verbs]).to include("code_semantic_search", "list_audit_logs")
      expect(described_class.fetch("powernode-concierge")[:role]).to include(read_only: false, server_grant: false)
      expect(described_class.fetch("powernode-concierge")[:role][:verbs]).to include("list_agents", "platform_provisioning_capture_brief")
      expect(described_class.fetch("platform-engineer")[:role]).to include(read_only: false, server_grant: true)
    end

    # The concierge may contribute (additive, attributable) but not curate: the
    # curation verbs live in skills of a domain outside its ceiling, which the
    # engineer's ceiling keeps. Done in the SKILLS, not the grant.
    it "keeps the concierge to additive writes; the curation verbs stay with the engineer" do
      additive = %w[create_knowledge create_learning rate_knowledge reinforce_learning dispute_learning
                    platform_provisioning_capture_brief send_message invite_agent]
      curation = %w[promote_knowledge update_knowledge resolve_contradiction unsupersede_learning verify_learning
                    verify_learning_batch extract_to_knowledge_graph]
      concierge = described_class.fetch("powernode-concierge")
      entries = Ai::Skills::CapabilitySeeder.load_entries(Rails.root.join("db", "seeds", "capability_skills"))
      verbs_in = ->(domains) { entries.select { |e| domains.include?(e["domain"]) }.flat_map { |e| e["manifest"]["verbs"] } }

      expect(concierge[:role][:verbs]).to include(*additive)
      expect(concierge[:role][:verbs] & curation).to be_empty
      expect(verbs_in.call(concierge[:domains]) & curation).to be_empty
      expect(Ai::Skills::Contract::CORE_DOMAINS).to include("knowledge-curation")
      expect(concierge[:domains]).not_to include("knowledge-curation")
      expect(curation - verbs_in.call(described_class.fetch("platform-engineer")[:domains])).to be_empty
    end

    it "keeps the domain ceilings of the design: concierge, engineer and reviewer" do
      expect(described_class.fetch("powernode-concierge")[:domains]).to match_array(%w[front-door knowledge external-agent-session])
      expect(described_class.fetch("platform-reviewer")[:domains]).to match_array(%w[review knowledge])
      expect(described_class.fetch("platform-engineer")[:domains]).not_to include("front-door")
      expect(described_class.fetch("platform-engineer")[:domains]).to include("software-engineering", "powernode-platform-dev", "review", "knowledge")
    end
  end

  describe "charters (assembly prompts)" do
    it "are at most 25 lines: identity, assembly protocol, duty, escalation, report, and no domain knowledge" do
      described_class.each do |slug, spec, _owner|
        lines = spec[:charter].lines.reject { |l| l.strip.empty? }
        expect(lines.size).to be <= 25, "#{slug} charter is #{lines.size} lines"
        expect(spec[:charter]).to include("assemble_task"), slug
        expect(spec[:charter]).to include("route_task"), slug
        expect(spec[:charter]).to include("record_agent_execution"), slug
        expect(spec[:charter]).not_to include("manifest"), slug
      end
    end
  end

  describe "absorbs (the old canonical slug each roster agent replaces)" do
    it "declares the operator-approved core map" do
      expect(described_class.fetch("platform-engineer")[:absorbs]).to match_array(
        %w[platform-developer platform-architect release-manager documentation-specialist prd-generator
           strategic-planner research-analyst knowledge-graph-curator]
      )
      expect(described_class.fetch("platform-reviewer")[:absorbs]).to match_array(%w[llm-judge system-quality-assurance])
      expect(described_class.fetch("powernode-concierge")[:absorbs]).to match_array(
        %w[system-concierge infrastructure-generalist powernode-assistant]
      )
    end

    it "looks an old slug up to its absorbing roster agent, nil for anything else" do
      expect(described_class.absorbing("llm-judge")).to eq("platform-reviewer")
      expect(described_class.absorbing(:"prd-generator")).to eq("platform-engineer")
      expect(described_class.absorbing("system-concierge")).to eq("powernode-concierge")
      expect(described_class.absorbing("platform-engineer")).to be_nil
      expect(described_class.absorbing("no-such-agent")).to be_nil
    end

    it "maps every old slug to exactly one roster agent, and no agent absorbs itself" do
      absorbed = described_class.each.flat_map { |slug, spec, _| spec[:absorbs].map { |old| [ old, slug ] } }
      expect(absorbed.map(&:first)).to eq(absorbed.map(&:first).uniq)
      expect(absorbed.select { |old, slug| old == slug }).to be_empty
      expect(absorbed.map(&:first) & described_class.slugs).to be_empty
    end

    it "refuses a spec that absorbs itself" do
      registry = with_registry
      expect { registry.register("a-one", spec_for("a-one", absorbs: %w[a-one]), owner: "core") }
        .to raise_error(ArgumentError, /absorb itself/)
    end

    it "refuses an old slug two roster agents both claim" do
      registry = with_registry("a-one" => spec_for("a-one", absorbs: %w[old-x]))
      expect { registry.register("b-two", spec_for("b-two", absorbs: %w[old-x]), owner: "core") }
        .to raise_error(described_class::DuplicateAbsorption, /old-x/)
    end

    it "lets the same agent re-register its absorbs (a code reload)" do
      registry = with_registry("a-one" => spec_for("a-one", absorbs: %w[old-x]))
      expect { registry.register("a-one", spec_for("a-one", absorbs: %w[old-x]), owner: "core") }.not_to raise_error
      expect(described_class.absorbing("old-x")).to eq("a-one")
    end
  end

  describe "the registry" do
    it "registers a spec under a slug and owner and yields it from #each, in registration order" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("b-two", spec_for("b-two"), owner: "extensions/example")

      expect(described_class.each.map { |slug, _spec, owner| [ slug, owner ] }).to eq([ %w[a-one core], %w[b-two extensions/example] ])
      expect(described_class.slugs).to eq(%w[a-one b-two])
      expect(described_class.fetch("b-two")[:name]).to eq("B Two")
      expect(described_class.include?("a-one")).to be(true)
    end

    it "filters #each by owner" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("b-two", spec_for("b-two"), owner: "extensions/example")

      expect(described_class.each(owner: "extensions/example").map { |slug, *| slug }).to eq(%w[b-two])
    end

    it "re-registering the same slug from the same owner replaces it (a code reload re-runs the engine hook)" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("a-one", spec_for("a-one", description: "Changed."), owner: "core")

      expect(described_class.fetch("a-one")[:description]).to eq("Changed.")
      expect(described_class.slugs).to eq(%w[a-one])
    end

    it "refuses a slug already owned by another owner" do
      registry = with_registry("a-one" => spec_for("a-one"))

      expect { registry.register("a-one", spec_for("a-one"), owner: "extensions/example") }
        .to raise_error(described_class::DuplicateSlug, /a-one/)
    end

    it "refuses a spec missing a required key, or with an unknown tier or domain list" do
      registry = with_registry

      expect { registry.register("x", spec_for("x").except(:charter), owner: "core") }.to raise_error(ArgumentError, /charter/)
      expect { registry.register("x", spec_for("x", tier: "huge"), owner: "core") }.to raise_error(ArgumentError, /tier/)
      expect { registry.register("x", spec_for("x", domains: []), owner: "core") }.to raise_error(ArgumentError, /domains/)
    end

    it "raises KeyError from #fetch for a slug nobody registered" do
      with_registry
      expect { described_class.fetch("platform-developer") }.to raise_error(KeyError)
    end

    it "no longer exposes the SURVIVORS/SLUGS constants (clean re-implementation, no alias)" do
      expect(described_class.constants).not_to include(:SURVIVORS, :SLUGS)
    end
  end
end
