# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# E2 follow-through — the generated MCP tool catalog publishes each action's
# safety annotations from the SAME Mcp::ToolCatalog derivation that tools/list
# sends. Before this, the document an operator sizes a grant from carried each
# action's permission and parameters but not whether the verb is a read, a
# reversible write or a destroy.
#
# The oracle is the catalog object, never a hardcoded verb's current
# declaration. Every rendered line must equal what Mcp::ToolCatalog publishes
# for that name, and the two named examples pick a declared read and a
# declared destroy out of the catalog's own entries.
# An action no declare_action record covers, contributed through the
# extension-tool seam so the core map is untouched. Duck-typed rather than an
# Ai::Tools::BaseTool subclass, like the fixture in
# spec/lib/tasks/mcp_tool_catalog_extension_tools_spec.rb: it implements only
# what the generator and Mcp::ToolCatalog read, and having no .declared_action
# is what puts it on the inferred path. File scope and a distinctive name for
# the reason that spec gives.
class McpToolCatalogUndeclaredFixtureTool
  REQUIRED_PERMISSION = "fixture.undeclared.read"
  ACTION_PERMISSIONS = {}.freeze

  def self.permitted?(**_options) = true

  def self.definition
    { name: "fixture_undeclared_widget", description: "Undeclared fixture action.", parameters: {} }
  end

  def self.action_definitions
    { "fixture_undeclared_widget" => { description: "Undeclared fixture action.", parameters: {} } }
  end
end

RSpec.describe "rails mcp:generate_tool_catalog renders safety annotations" do
  # The rake lives in lib/ unless a mutation run points elsewhere.
  def self.rake_lib = ENV["MCP_CATALOG_RAKE_LIB"].presence || Rails.root.join("lib").to_s

  # Runs the real task into a throwaway path and returns the document.
  def self.generate_markdown
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mcp-tools.md")
      previous_application = Rake.application
      original_stdout = $stdout
      begin
        Rake.application = Rake::Application.new
        Rake.application.rake_require("tasks/mcp_tool_catalog", [ rake_lib ], [])
        Rake::Task.define_task(:environment)
        ENV["MCP_TOOL_CATALOG_OUTPUT"] = path
        $stdout = StringIO.new
        Rake::Task["mcp:generate_tool_catalog"].invoke
      ensure
        $stdout = original_stdout
        ENV.delete("MCP_TOOL_CATALOG_OUTPUT")
        Rake.application = previous_application
      end
      File.read(path)
    end
  end

  # Generated ONCE for the group: the task walks the whole registry.
  def self.generated
    @generated ||= generate_markdown
  end

  # action name => the text after "- **Annotations**: ", or nil when its
  # section has no such line.
  def self.sections(markdown)
    out = {}
    current = nil
    markdown.each_line do |line|
      if (m = line.match(/\A### `([a-z0-9_]+)`\s*\z/))
        current = m[1]
        out[current] = nil
      elsif current && (m = line.chomp.match(/\A- \*\*Annotations\*\*: (.*)\z/))
        out[current] = m[1].strip
      end
    end
    out
  end

  def self.rendered
    @rendered ||= sections(generated)
  end

  def self.published_entries
    @published_entries ||= Mcp::ToolCatalog.new(protocol_version: Mcp::ToolCatalog::DESCRIBE_PROTOCOL_VERSION)
                                            .entries.index_by { |entry| entry["name"] }
  end

  def published(action) = self.class.published_entries["#{Mcp::ToolCatalog::PLATFORM_PREFIX}#{action}"]&.dig("annotations")

  # Parses a rendered line BACK into the hash it claims to state, so the
  # comparison is hash to hash and this file does not keep a second copy of
  # the rendering rule.
  def parse(text)
    return nil if text.nil? || text == "not published"

    text.scan(/`([A-Za-z]+): ([^`]+)`/).to_h do |key, value|
      [ key, { "true" => true, "false" => false }.fetch(value, value) ]
    end
  end

  def pick(&predicate)
    name, entry = self.class.published_entries.find { |_, e| e["annotations"].is_a?(Hash) && predicate.call(e["annotations"]) }
    raise "the catalog published no entry of this shape — the oracle has nothing to measure" unless entry

    name.delete_prefix(Mcp::ToolCatalog::PLATFORM_PREFIX)
  end

  it "renders an annotations line in every action section of a real corpus" do
    expect(self.class.rendered.size).to be > 500
    missing = self.class.rendered.select { |_, text| text.nil? }.keys
    expect(missing).to be_empty, "#{missing.size} section(s) carry no annotations line: #{missing.first(10).join(', ')}"
  end

  it "renders a declared read as read-only, with no destructiveHint" do
    action = pick { |a| a["annotationSource"] == "declared" && a["readOnlyHint"] == true }

    expect(parse(self.class.rendered[action])).to eq("readOnlyHint" => true, "annotationSource" => "declared")
  end

  it "renders a declared destroy as a destructive write" do
    action = pick { |a| a["annotationSource"] == "declared" && a["destructiveHint"] == true }

    expect(parse(self.class.rendered[action]))
      .to eq("readOnlyHint" => false, "destructiveHint" => true, "annotationSource" => "declared")
  end

  it "publishes, for every action, exactly the annotations tools/list sends" do
    mismatched = self.class.rendered.filter_map do |action, text|
      "#{action}: rendered #{parse(text).inspect}, tools/list #{published(action).inspect}" unless parse(text) == published(action)
    end

    expect(mismatched).to be_empty, "#{mismatched.size} mismatch(es):\n  #{mismatched.first(10).join("\n  ")}"
  end

  # THE INFERRED PATH. Every row the examples above read is declared: the 9
  # inferred entries tools/list sends are the introspection family, which this
  # document does not render. So none of them could tell a generator that
  # stamps every row "declared" from one that reports the source it was given.
  # This registers an action with no declare_action record and reads its row.
  context "for an action with no declaration" do
    def undeclared_action = "fixture_undeclared_widget"

    around do |example|
      ::Ai::Tools::PlatformApiToolRegistry.register_extension_tools(undeclared_action => "McpToolCatalogUndeclaredFixtureTool")
      example.run
    ensure
      ::Ai::Tools::PlatformApiToolRegistry.extension_tools.delete(undeclared_action)
    end

    it "renders the inferred source tools/list sends for it, not a stamped declared" do
      published = Mcp::ToolCatalog.new(protocol_version: Mcp::ToolCatalog::DESCRIBE_PROTOCOL_VERSION)
                                  .entries
                                  .find { |entry| entry["name"] == "#{Mcp::ToolCatalog::PLATFORM_PREFIX}#{undeclared_action}" }
                                  &.dig("annotations")
      # Oracle guard: the fixture must actually reach the inferred path.
      expect(published).to include("annotationSource" => "inferred")

      rendered = self.class.sections(self.class.generate_markdown)[undeclared_action]
      expect(parse(rendered)).to eq(published)
    end
  end
end
