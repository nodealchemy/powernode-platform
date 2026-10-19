# frozen_string_literal: true

require "rails_helper"

# C3-1 — every registry action carries a DECLARED tool family. Before this the
# only taxonomy was the name prefix (tool_families scoping, ToolRelevanceFilter)
# and a catalog map keyed by class name, under which 440 of 674 actions rendered
# as "Uncategorized". The family is declared once — a class default
# (`tool_family`) or a per-action `declare_action ... family:` override — and
# must be a key of Ai::Tools::ToolFamilies, which core and extensions extend
# through the same seam.
#
# The walk is PlatformApiToolRegistry.all_tools, so extension-registered tool
# maps are covered by construction. A class that does not load (core mode
# without the extension that owns it) is not served and is skipped; the
# registry already drops it from every advertised surface.
RSpec.describe "declared tool families" do
  let(:registry) { Ai::Tools::PlatformApiToolRegistry }

  def loadable_actions
    registry.all_tools.select { |_, class_name| class_name.safe_constantize }
  end

  it "resolves every registered action to a non-blank family from the known set" do
    offenders = loadable_actions.keys.filter_map do |name|
      family = registry.family_for(name)
      "#{name} (#{registry.all_tools[name]}): #{family.inspect}" unless Ai::Tools::ToolFamilies.known?(family)
    end

    expect(offenders).to be_empty, "actions without a declared, known family:\n  #{offenders.join("\n  ")}"
  end

  it "keeps the vocabulary small enough to browse" do
    expect(Ai::Tools::ToolFamilies.all.size).to be_between(15, 25)
  end

  it "leaves no known family empty, so every key names real surface" do
    empty = Ai::Tools::ToolFamilies.all.keys - registry.families.keys

    expect(empty).to be_empty, "families nothing declares: #{empty.inspect}"
  end

  it "indexes every loadable action under exactly one family" do
    indexed = registry.families.values.flatten

    expect(indexed).to match_array(loadable_actions.keys)
  end

  # The resolution order, on a synthetic class so it cannot pass by accident
  # against whatever the real tools happen to declare.
  describe "resolution" do
    let(:tool_class) do
      Class.new(Ai::Tools::BaseTool) do
        tool_family "knowledge"
        declare_action "plain_read", mutating: false
        declare_action "moved_read", mutating: false, family: "skills"
      end
    end

    it "uses the class default for an action that names no family" do
      expect(tool_class.family_for("plain_read")).to eq("knowledge")
      expect(tool_class.family_for("never_declared")).to eq("knowledge")
    end

    it "lets a declaration override the class default" do
      expect(tool_class.family_for("moved_read")).to eq("skills")
    end

    it "inherits the class default" do
      expect(Class.new(tool_class).family_for("plain_read")).to eq("knowledge")
    end

    it "answers nil for a class that declares no family, which the lint above rejects" do
      expect(Class.new(Ai::Tools::BaseTool).family_for("anything")).to be_nil
      expect(Ai::Tools::ToolFamilies.known?(nil)).to be(false)
    end

    it "looks an override up under the dispatched name of an aliased registry key" do
      aliased, dispatched = Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.first
      klass = registry.all_tools[aliased].constantize
      allow(klass).to receive(:family_for).and_call_original

      registry.family_for(aliased)

      expect(klass).to have_received(:family_for).with(dispatched)
    end
  end

  describe Ai::Tools::ToolFamilies do
    after { described_class.extension_families.delete("lint_fixture_family") }

    it "accepts an extension's families through .register without a core edit" do
      described_class.register("lint_fixture_family" => "Lint fixture")

      expect(described_class.known?("lint_fixture_family")).to be(true)
      expect(described_class.label("lint_fixture_family")).to eq("Lint fixture")
    end

    it "refuses to let an extension relabel a core family" do
      core_key = described_class::CORE.keys.first

      expect { described_class.register(core_key => "Hijacked") }.to raise_error(ArgumentError, /core family/)
    end
  end
end
