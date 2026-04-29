# frozen_string_literal: true

require "rails_helper"

# The extensions_loader_helper lives at the project root (../) so that the
# Gemfile can require it before any Rails autoloading is available.
require File.expand_path("../../../extensions_loader_helper", __dir__)

RSpec.describe "discover_extension_gems" do
  let(:project_root) { File.expand_path("../..", __dir__) }
  let(:state_file) { File.join(project_root, "config", "extensions_state.json") }

  describe "respects config/extensions_state.json disabled list" do
    around do |example|
      original = File.exist?(state_file) ? File.read(state_file) : nil
      example.run
    ensure
      if original
        File.write(state_file, original)
      else
        File.delete(state_file) if File.exist?(state_file)
      end
    end

    it "excludes a slug listed under disabled" do
      FileUtils.mkdir_p(File.dirname(state_file))
      File.write(state_file, JSON.generate("disabled" => ["trading"]))

      slugs = discover_extension_gems.map(&:first)

      expect(slugs).not_to include("trading")
    end

    it "includes a slug not listed under disabled" do
      FileUtils.mkdir_p(File.dirname(state_file))
      File.write(state_file, JSON.generate("disabled" => ["trading"]))

      # Business and supply-chain are present in this checkout; only trading is filtered
      slugs = discover_extension_gems.map(&:first)

      expect(slugs).to include("business") if File.exist?(File.join(project_root, "extensions/business/extension.json"))
      expect(slugs).to include("supply-chain") if File.exist?(File.join(project_root, "extensions/supply-chain/extension.json"))
    end

    it "treats missing state file as empty disabled list" do
      File.delete(state_file) if File.exist?(state_file)

      slugs = discover_extension_gems.map(&:first)

      expect(slugs).to include("business") if File.exist?(File.join(project_root, "extensions/business/extension.json"))
    end

    it "treats malformed state file as empty disabled list" do
      FileUtils.mkdir_p(File.dirname(state_file))
      File.write(state_file, "not-valid-json {{{")

      expect { discover_extension_gems }.not_to raise_error
    end
  end
end
