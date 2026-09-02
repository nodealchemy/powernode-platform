# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# IMP-86c839455f87 — the generated MCP tool catalog must be sourced from the
# SAME map the runtime uses.
#
# `Ai::Tools::PlatformApiToolRegistry::TOOLS` is the static core map;
# `.all_tools` is `TOOLS.merge(extension_tools)` (platform_api_tool_registry.rb),
# and every runtime consumer reads `.all_tools`:
# `McpPlatformToolRegistrar.sync_to_database!`, `.tool_classes`,
# `.find_tool_class` and `PlatformApiToolRegistry.available_tools`. The
# generator in server/lib/tasks/mcp_tool_catalog.rake read `TOOLS`, so a tool
# contributed through the `register_extension_tools` seam was written to the
# `mcp_tools` table, executable via `find_tool_class`, and advertised over MCP —
# yet structurally absent from docs/reference/auto/mcp-tools.md, the surface an
# operator reads when sizing an MCP grant.
#
# HONEST POPULATION, AND ITS SCOPE: measured in the PUBLIC bundle (the default,
# and the one the committed catalog is generated in), `extension_tools.size == 0`
# and `all_tools.keys - TOOLS.keys == []`, so the divergence costs the tracked
# artifact zero rows TODAY. That measurement does NOT generalise to every
# environment: a private-mode bundle (`BUNDLE_GEMFILE=Gemfile.private`, which sets
# POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1) or a deployed node (POWERNODE_DEPLOYED=1)
# loads extension engines that DO register through the seam, and there the
# divergence was real rather than latent. This spec is bundle-independent — it
# registers its own fixture and compares the generated file against `.all_tools`
# as measured in the same process, so it holds either way. For the tracked
# artifact this is a drift guard, not a live documentation gap: it fires the
# first time any extension registers a tool, and nothing else would warn —
# scripts/check-mcp-catalog-fresh.sh only proves the doc is consistent with the
# source it declares, which was the narrow one.
#
# Because that population is empty in the public bundle, a spec over the
# committed catalog cannot see
# this at all. The only oracle that can is one that REGISTERS an extension tool
# and runs the generator, which is what this file does — into a temp path, so
# the committed catalog is never touched.

# Stands in for a tool class an extension engine would contribute. Defined at
# file scope (not inside an RSpec block, where a constant lands on Object and a
# same-named constant in another spec file can clobber it) and named
# distinctively for the same reason. It implements exactly the surface the
# generator touches: .action_definitions, .definition, and the two permission
# constants Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for reads.
class McpToolCatalogExtensionFixtureTool
  REQUIRED_PERMISSION = "fixture.extension.read"
  ACTION_PERMISSIONS = { "fixture_extension_action" => "fixture.extension.manage" }.freeze

  def self.definition
    { name: "fixture_extension_action", description: "fixture tool", parameters: {} }
  end

  def self.action_definitions
    {
      "fixture_extension_action" => {
        description: "Fixture action contributed through the extension-tool seam.",
        parameters: {
          fixture_param: { type: "string", required: true, description: "fixture parameter" }
        }
      }
    }
  end
end

RSpec.describe "mcp:generate_tool_catalog sources extension-registered tools" do
  # Methods, not constants: a constant assigned inside an RSpec block lands on
  # Object, where a same-named constant in another spec file can clobber it.
  def action_name
    "fixture_extension_action"
  end

  def fixture_class_name
    "McpToolCatalogExtensionFixtureTool"
  end

  let(:registry) { ::Ai::Tools::PlatformApiToolRegistry }

  # Runs the real rake task against a throwaway output path. A private
  # Rake::Application is used rather than Rails.application.load_tasks so this
  # neither depends on nor mutates global Rake state, and `:environment` is
  # stubbed out because the spec is already booted.
  def generate_catalog
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mcp-tools.md")
      previous_application = Rake.application
      begin
        Rake.application = Rake::Application.new
        Rake.application.rake_require("tasks/mcp_tool_catalog", [Rails.root.join("lib").to_s], [])
        Rake::Task.define_task(:environment)
        ENV["MCP_TOOL_CATALOG_OUTPUT"] = path
        silence_stream { Rake::Task["mcp:generate_tool_catalog"].invoke }
      ensure
        ENV.delete("MCP_TOOL_CATALOG_OUTPUT")
        Rake.application = previous_application
      end
      File.read(path)
    end
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  # Parse the `### \`action\`` headings the generator emits — the same markup
  # spec/lib/tasks/mcp_tool_catalog_permission_spec.rb reads out of the
  # committed file.
  def published_actions(markdown)
    markdown.scan(/^### `([a-z0-9_]+)`\s*$/).flatten
  end

  around do |example|
    registry.register_extension_tools(action_name => fixture_class_name)
    example.run
  ensure
    registry.extension_tools.delete(action_name)
  end

  it "puts the fixture in all_tools only, never in the static core map" do
    # Oracle guard. If the fixture leaked into TOOLS this whole file would pass
    # against the narrow-source generator it exists to catch.
    expect(registry.extension_tools).to include(action_name => fixture_class_name)
    expect(registry.all_tools).to include(action_name => fixture_class_name)
    expect(registry::TOOLS).not_to have_key(action_name)
  end

  it "publishes an extension-registered action in the generated catalog" do
    actions = published_actions(generate_catalog)

    expect(actions).to include(action_name),
      "the generated catalog omits #{action_name}, which .all_tools carries and the DB registrar syncs — " \
      "the generator is still sourcing the narrower Ai::Tools::PlatformApiToolRegistry::TOOLS"
  end

  it "publishes the extension action's class and resolved ladder permission" do
    markdown = generate_catalog
    section = markdown[/^### `#{action_name}`\n.*?(?=^### |\z)/m]

    expect(section).to be_present
    expect(section).to include("- **Tool class**: `#{fixture_class_name}`")
    # The per-action ladder entry, not the class floor — the extension path must
    # go through the same Ai::Tools::McpPlatformToolRegistrar.resolved_permission_for
    # resolution as core tools (IMP-a63365dc0f41 / IMP-bab07f770c0e).
    expect(section).to include("- **Permission**: fixture.extension.manage")
    expect(section).not_to include("- **Permission**: #{McpToolCatalogExtensionFixtureTool::REQUIRED_PERMISSION}")
  end

  it "counts every action in all_tools, not just the core ones" do
    markdown = generate_catalog

    expect(published_actions(markdown).size).to eq(registry.all_tools.size)
    expect(markdown).to include("**#{registry.all_tools.size} actions**")
  end

  it "declares the merged map as its source in the generated header" do
    # The header is what a reader (and the freshness checker's own comment)
    # takes as the catalog's source of truth; leaving it naming ::TOOLS would
    # re-describe the narrow source this change removed.
    markdown = generate_catalog

    expect(markdown[/^> Source: .*$/]).to eq("> Source: `Ai::Tools::PlatformApiToolRegistry.all_tools`")
    # And it must say that the merged map's contents depend on which extension
    # engines were loaded, so a reader cannot mistake a locally generated copy
    # for the committed public-bundle rendering.
    expect(markdown[/^> Scope: .*$/]).to include("The committed copy is the public-bundle rendering")
  end

  it "omits the fixture once the extension deregisters it" do
    # Causation guard: proves the fixture's presence above comes from the
    # registration, not from the fixture class merely being defined.
    registry.extension_tools.delete(action_name)

    expect(published_actions(generate_catalog)).not_to include(action_name)
  end
end
