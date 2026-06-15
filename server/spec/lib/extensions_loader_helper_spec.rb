# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

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

      expect(slugs).to include("business") if File.exist?(File.join(project_root, "extensions/private/business/extension.json"))
      expect(slugs).to include("supply-chain") if File.exist?(File.join(project_root, "extensions/supply-chain/extension.json"))
    end

    it "treats missing state file as empty disabled list" do
      File.delete(state_file) if File.exist?(state_file)

      slugs = discover_extension_gems.map(&:first)

      expect(slugs).to include("business") if File.exist?(File.join(project_root, "extensions/private/business/extension.json"))
    end

    it "treats malformed state file as empty disabled list" do
      FileUtils.mkdir_p(File.dirname(state_file))
      File.write(state_file, "not-valid-json {{{")

      expect { discover_extension_gems }.not_to raise_error
    end
  end
end

# Visibility coverage: the public/private split that backs the public-only
# Gemfile.lock guarantee (a maintainer machine with private extensions on disk
# must still produce a public-only lock). Driven against a throwaway fixture
# root via the injectable base_dir, so it is deterministic regardless of which
# extensions are checked out and never touches the real tree.
RSpec.describe "discover_extension_gems_by_visibility (public/private split)" do
  attr_reader :root

  around do |example|
    Dir.mktmpdir("ext-loader-spec") do |dir|
      @root = dir
      build_fixture(dir)
      saved = ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"]
      ENV.delete("POWERNODE_INCLUDE_PRIVATE_EXTENSIONS")
      begin
        example.run
      ensure
        if saved.nil?
          ENV.delete("POWERNODE_INCLUDE_PRIVATE_EXTENSIONS")
        else
          ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] = saved
        end
      end
    end
  end

  # alpha/beta:   public (declared in .gitmodules), server engines.
  # gamma:        private (on disk, NOT in .gitmodules), server engine.
  # disabled:     server engine, listed disabled in extensions_state.json.
  # frontendonly: no server component -> never a path gem.
  def build_fixture(root)
    %w[alpha beta gamma disabled].each { |s| make_extension(root, s, server: true) }
    make_extension(root, "frontendonly", server: false)

    File.write(File.join(root, ".gitmodules"), <<~GITMODULES)
      [submodule "extensions/alpha"]
        path = extensions/alpha
        url = https://github.com/example/alpha.git
      [submodule "extensions/beta"]
        path = extensions/beta
        url = https://github.com/example/beta.git
    GITMODULES

    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "extensions_state.json"),
               JSON.generate("disabled" => ["disabled"]))
  end

  def make_extension(root, slug, server:)
    ext = File.join(root, "extensions", slug)
    FileUtils.mkdir_p(ext)
    File.write(File.join(ext, "extension.json"),
               JSON.generate("components" => { "server" => server }))
    FileUtils.mkdir_p(File.join(ext, "server")) if server
  end

  describe "#public_extension_slugs" do
    it "returns exactly the slugs declared in .gitmodules" do
      expect(public_extension_slugs(root)).to contain_exactly("alpha", "beta")
    end

    it "returns [] when .gitmodules is absent (stripped checkout)" do
      FileUtils.rm_f(File.join(root, ".gitmodules"))
      expect(public_extension_slugs(root)).to eq([])
    end
  end

  describe "#discover_extension_gems_by_visibility" do
    it "buckets .gitmodules-declared extensions as public, sorted" do
      expect(discover_extension_gems_by_visibility(root)[:public]).to eq(
        [["alpha", "../extensions/alpha/server"], ["beta", "../extensions/beta/server"]]
      )
    end

    it "excludes private extensions from the lock by default (the public-only guarantee)" do
      expect(discover_extension_gems_by_visibility(root)[:private]).to be_empty
    end

    it "includes private extensions only when explicitly opted in" do
      ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] = "1"
      result = discover_extension_gems_by_visibility(root)
      expect(result[:public]).to eq(
        [["alpha", "../extensions/alpha/server"], ["beta", "../extensions/beta/server"]]
      )
      expect(result[:private]).to eq([["gamma", "../extensions/gamma/server"]])
    end

    it "excludes a disabled extension even when it is public and opted in" do
      # Promote `disabled` to public, then prove the disabled-list still wins.
      File.write(
        File.join(root, ".gitmodules"),
        File.read(File.join(root, ".gitmodules")) +
        %([submodule "extensions/disabled"]\n  path = extensions/disabled\n  url = x\n)
      )
      ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] = "1"
      slugs = discover_extension_gems_by_visibility(root).values.flatten(1).map(&:first)
      expect(slugs).not_to include("disabled")
    end

    it "skips extensions without a server component" do
      ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] = "1"
      slugs = discover_extension_gems_by_visibility(root).values.flatten(1).map(&:first)
      expect(slugs).not_to include("frontendonly")
    end

    it "treats every extension as private when .gitmodules is absent (so default = none)" do
      FileUtils.rm_f(File.join(root, ".gitmodules"))
      expect(discover_extension_gems_by_visibility(root)).to eq(public: [], private: [])
    end

    it "returns empty buckets when extensions/ is absent" do
      FileUtils.rm_rf(File.join(root, "extensions"))
      expect(discover_extension_gems_by_visibility(root)).to eq(public: [], private: [])
    end
  end

  describe "#discover_extension_gems (flat, base_dir)" do
    it "is public-only by default (matches the committed Gemfile.lock)" do
      expect(discover_extension_gems(root)).to eq(
        [["alpha", "../extensions/alpha/server"], ["beta", "../extensions/beta/server"]]
      )
    end

    it "flattens public + private into the path-gem list when opted in" do
      ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] = "1"
      expect(discover_extension_gems(root)).to eq(
        [
          ["alpha", "../extensions/alpha/server"],
          ["beta", "../extensions/beta/server"],
          ["gamma", "../extensions/gamma/server"]
        ]
      )
    end
  end
end
