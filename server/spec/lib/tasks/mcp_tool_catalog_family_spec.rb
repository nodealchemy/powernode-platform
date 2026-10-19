# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# C3-1 — the generated catalog is sectioned by DECLARED tool family
# (Ai::Tools::PlatformApiToolRegistry.family_for), not by a class-name map kept
# inside the generator, which left 440 of 674 actions under "Uncategorized".
RSpec.describe "mcp:generate_tool_catalog groups by declared family" do
  let(:registry) { Ai::Tools::PlatformApiToolRegistry }

  def generate_catalog
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mcp-tools.md")
      previous_application = Rake.application
      begin
        Rake.application = Rake::Application.new
        Rake.application.rake_require("tasks/mcp_tool_catalog", [ Rails.root.join("lib").to_s ], [])
        Rake::Task.define_task(:environment)
        ENV["MCP_TOOL_CATALOG_OUTPUT"] = path
        original = $stdout
        $stdout = StringIO.new
        Rake::Task["mcp:generate_tool_catalog"].invoke
      ensure
        $stdout = original
        ENV.delete("MCP_TOOL_CATALOG_OUTPUT")
        Rake.application = previous_application
      end
      File.read(path)
    end
  end

  # section heading => actions listed under it
  def sections(markdown)
    markdown.split(/^## /).drop(1).to_h do |chunk|
      [ chunk.lines.first.strip, chunk.scan(/^### `([a-z0-9_]+)`\s*$/).flatten ]
    end
  end

  it "renders no Uncategorized section" do
    expect(sections(generate_catalog).keys).not_to include("Uncategorized")
  end

  it "files every action under the heading of its declared family" do
    misfiled = sections(generate_catalog).flat_map do |heading, actions|
      actions.filter_map do |action|
        family = registry.family_for(action)
        expected = "#{Ai::Tools::ToolFamilies.label(family)} (`#{family}`)"
        "#{action}: under #{heading.inspect}, declared #{expected.inspect}" unless heading == expected
      end
    end

    expect(misfiled).to be_empty, misfiled.first(10).join("\n")
  end
end
