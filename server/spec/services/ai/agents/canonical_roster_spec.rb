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
      domains: %w[knowledge], role: { code: false, shell: false, server_grant: false, duty: "Do the duty." },
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
        expect(spec[:role].keys).to match_array(%i[code shell server_grant duty])
      end
    end

    it "pins the roster tiers: concierge and engineer standard, reviewer reasoning" do
      expect(core_slugs.to_h { |s| [ s, described_class.fetch(s)[:tier] ] })
        .to eq("powernode-concierge" => "standard", "platform-engineer" => "standard", "platform-reviewer" => "reasoning")
    end

    it "gives the reviewer a shell but never Edit/Write, and says so in its charter" do
      reviewer = described_class.fetch("platform-reviewer")

      expect(reviewer[:role]).to include(code: false, shell: true)
      expect(reviewer[:charter]).to match(/read-only git/i)
      expect(reviewer[:charter]).to match(/never edit, commit/i)
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

  describe "the registry" do
    it "registers a spec under a slug and owner and yields it from #each, in registration order" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("b-two", spec_for("b-two"), owner: "extensions/system")

      expect(described_class.each.map { |slug, _spec, owner| [ slug, owner ] }).to eq([ %w[a-one core], %w[b-two extensions/system] ])
      expect(described_class.slugs).to eq(%w[a-one b-two])
      expect(described_class.fetch("b-two")[:name]).to eq("B Two")
      expect(described_class.include?("a-one")).to be(true)
    end

    it "filters #each by owner" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("b-two", spec_for("b-two"), owner: "extensions/system")

      expect(described_class.each(owner: "extensions/system").map { |slug, *| slug }).to eq(%w[b-two])
    end

    it "re-registering the same slug from the same owner replaces it (a code reload re-runs the engine hook)" do
      registry = with_registry("a-one" => spec_for("a-one"))
      registry.register("a-one", spec_for("a-one", description: "Changed."), owner: "core")

      expect(described_class.fetch("a-one")[:description]).to eq("Changed.")
      expect(described_class.slugs).to eq(%w[a-one])
    end

    it "refuses a slug already owned by another owner" do
      registry = with_registry("a-one" => spec_for("a-one"))

      expect { registry.register("a-one", spec_for("a-one"), owner: "extensions/system") }
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
