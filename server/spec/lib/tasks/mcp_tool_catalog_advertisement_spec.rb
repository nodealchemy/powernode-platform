# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# Increment E2 — the generated catalog publishes what MCP actually OFFERS.
#
# `docs/reference/auto/mcp-tools.md` is the surface an operator reads when
# sizing an MCP grant. The generator walked the raw registry map, while every
# runtime door — tools/list, Mcp::ToolCatalog, and
# McpPlatformToolRegistrar#unadvertised_refusal — filters that map through
# `PlatformApiToolRegistry.advertised_action?`. So the document could list an
# action that answers "Tool not available: … is not offered by this control
# plane" when called, and an operator could grant a pattern for a verb that
# does not exist in their bundle. A privilege OVERSTATEMENT of the surface.
#
# WHY THIS SPEC HAS TO DRIVE THE PREDICATE. In the public bundle the filter
# removes ZERO rows today: `.permitted?(agent: nil)` short-circuits true, and
# the one class implementing `.action_advertised?`
# (Ai::Tools::DiskImageOperatorTool) gates two actions on the system extension,
# which IS loaded here. A filter that removes nothing is invisible to
# observation — it would pass identically whether it were wired up or deleted.
# Both arms are therefore driven with a stubbed predicate: the SAME fixture
# action is published when advertised and omitted when not.

# Stands in for an extension-contributed tool, at file scope for the same
# reason its sibling (mcp_tool_catalog_extension_tools_spec.rb) does it: a
# constant assigned inside an RSpec block lands on Object, where another spec
# file's same-named constant can clobber it.
# Subclasses BaseTool, unlike its sibling spec's deliberately-minimal fixture:
# `advertised_action?` asks the class `.permitted?`, so a fixture driving the
# ADVERTISEMENT filter has to be able to answer it. (The generator keeps rows
# for classes that cannot — see the rake task — which is what lets that sibling
# fixture stay minimal.)
class McpToolCatalogAdvertisementFixtureTool < ::Ai::Tools::BaseTool
  REQUIRED_PERMISSION = "fixture.advertisement.read"

  def self.definition
    { name: "fixture_advertised_action", description: "fixture tool", parameters: {} }
  end

  def self.action_definitions
    {
      "fixture_advertised_action" => {
        description: "Fixture action used to drive the advertisement filter.",
        parameters: {}
      }
    }
  end
end

RSpec.describe "mcp:generate_tool_catalog filters through advertised_action?" do
  def action_name
    "fixture_advertised_action"
  end

  def fixture_class_name
    "McpToolCatalogAdvertisementFixtureTool"
  end

  let(:registry) { ::Ai::Tools::PlatformApiToolRegistry }

  # The real rake task against a throwaway output path, so the committed
  # catalog is never touched. A private Rake::Application rather than
  # Rails.application.load_tasks, so global Rake state is neither read nor
  # mutated; `:environment` is stubbed because the spec is already booted.
  def generate_catalog
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mcp-tools.md")
      previous_application = Rake.application
      begin
        Rake.application = Rake::Application.new
        Rake.application.rake_require("tasks/mcp_tool_catalog", [ Rails.root.join("lib").to_s ], [])
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

  def published_actions(markdown)
    markdown.scan(/^### `([a-z0-9_]+)`\s*$/).flatten
  end

  around do |example|
    registry.register_extension_tools(action_name => fixture_class_name)
    example.run
  ensure
    registry.extension_tools.delete(action_name)
  end

  it "is in the registry map either way" do
    # Oracle guard: both arms below must differ because of the FILTER, not
    # because the fixture stopped being registered.
    expect(registry.all_tools).to include(action_name => fixture_class_name)
  end

  it "publishes an action the predicate advertises" do
    actions = published_actions(generate_catalog)

    expect(actions).to include(action_name)
  end

  it "omits an action the predicate refuses" do
    original = registry.method(:advertised_action?)
    allow(registry).to receive(:advertised_action?) do |name, klass, **kwargs|
      name.to_s == action_name ? false : original.call(name, klass, **kwargs)
    end

    actions = published_actions(generate_catalog)

    expect(actions).not_to include(action_name),
      "the generator still publishes #{action_name} after advertised_action? refused it — " \
      "the filter is not wired, and the document overstates the surface an operator can grant"
  end

  # The filter must not swallow a BROKEN registry entry. The generator renders
  # an unloadable class as "(class not found)", which is information the
  # operator wants; dropping it here would turn a broken entry into a silent
  # absence — the same class of defect this filter exists to remove, pointing
  # the other way.
  it "keeps a row whose class will not load" do
    registry.register_extension_tools("fixture_unloadable_action" => "No::Such::ToolClass")

    actions = published_actions(generate_catalog)

    expect(actions).to include("fixture_unloadable_action")
  ensure
    registry.extension_tools.delete("fixture_unloadable_action")
  end

  # What the filter costs the COMMITTED artifact today, measured rather than
  # assumed. Stated as a floor on the real surface so it cannot silently become
  # a filter that guts the document.
  it "removes nothing from the real public-bundle surface" do
    real = registry.all_tools.reject do |name, class_name|
      klass = class_name.safe_constantize
      klass.nil? || registry.advertised_action?(name, klass, agent: nil)
    end

    expect(real.keys - [ action_name ]).to be_empty,
      "advertised_action? now refuses #{real.size} real registry action(s): " \
      "#{real.keys.sort.join(', ')}. That may be correct — a bundle without the system " \
      "extension legitimately drops the two extension-backed disk-image actions — but it " \
      "changes what the committed catalog contains and needs a deliberate regeneration."
  end
end
