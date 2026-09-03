# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# IMP-fb5085178b09 — the generated MCP tool catalog must publish the SCHEMA a
# client is handed, not a prose-only subset of it.
#
# The tool surfaces declare closed value sets (`enum:`) and array element types
# (`items:`), and Ai::Tools::ParameterSchema carries both onto the MCP wire —
# `inputSchema` on tools/list (Api::V1::Mcp::StreamableHttpController) and on the
# mcp_tools rows / registry manifest (Ai::Tools::McpPlatformToolRegistrar). The
# generator in server/lib/tasks/mcp_tool_catalog.rake rendered only
# Parameter | Type | Required | Description straight off the raw declaration
# hash, so every one of those keywords was dropped: docs/reference/auto/mcp-tools.md
# stated `provider | string | Yes | DNS provider slug — the set
# System::AcmeDnsCredential validates on` and never the seven slugs the wire
# actually constrains it to. The catalog is the surface an operator reads when
# sizing an MCP grant and the only human-readable schema reference, so it
# understated the contract.
#
# The oracle is the SAME converter the wire uses — the generator now renders
# Ai::Tools::ParameterSchema.build's output rather than re-reading the authoring
# hash, which is why the wire's own array default (`items: {type: string}` filled
# in for an array that declares none) shows up here too. Pinned against a fixture
# tool registered through the extension seam, so it holds in any bundle, plus one
# spot check on the committed public-bundle artifact so a generator fix that is
# never regenerated into the tracked file cannot pass.

# Stands in for a tool an extension engine contributes. File scope and a
# distinctive name: a constant assigned inside an RSpec block lands on Object,
# where a same-named constant in another spec file can clobber it. Implements
# exactly the surface the generator touches.
class McpToolCatalogSchemaRenderingFixtureTool
  REQUIRED_PERMISSION = "fixture.schema.read"
  ACTION_PERMISSIONS = { "fixture_schema_action" => "fixture.schema.manage" }.freeze

  def self.definition
    { name: "fixture_schema_action", description: "fixture schema tool", parameters: {} }
  end

  def self.action_definitions
    {
      "fixture_schema_action" => {
        description: "Fixture action declaring closed value sets and array element types.",
        parameters: {
          mode: { type: "string", required: true, enum: %w[alpha beta gamma],
                  description: "closed value set" },
          separator: { type: "string", required: false, enum: [ "a|b", "c" ],
                       description: "value containing a table separator | character" },
          tags: { type: "array", required: false, items: { type: "string" },
                  description: "declared element type" },
          records: { type: "array", required: false, items: { type: "object" },
                     description: "object elements" },
          untyped_list: { type: "array", required: false,
                          description: "no declared elements" },
          scopes: { type: "array", required: false,
                    items: { type: "string", enum: %w[read write admin] },
                    description: "closed set on the ELEMENTS, not the array" },
          endpoint: { type: "object", required: false,
                      properties: {
                        host: { type: "string" },
                        record_type: { type: "string", enum: %w[A AAAA CNAME] }
                      },
                      description: "closed set one level down, on a nested property" },
          plain: { type: "string", required: false, description: "no closed set" }
        }
      }
    }
  end
end

RSpec.describe "mcp:generate_tool_catalog publishes declared enum/items" do
  # Methods, not constants — see the note on the fixture class above.
  def action_name
    "fixture_schema_action"
  end

  def fixture_class_name
    "McpToolCatalogSchemaRenderingFixtureTool"
  end

  let(:registry) { ::Ai::Tools::PlatformApiToolRegistry }

  # Runs the real rake task against a throwaway output path, through a private
  # Rake::Application so global Rake state is neither read nor mutated.
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

  def section_for(markdown, action)
    markdown[/^### `#{Regexp.escape(action)}`\n.*?(?=^### |\z)/m]
  end

  # Split on UNESCAPED pipes only: a cell whose content contains a `|` must have
  # escaped it, or the row silently grows a column and the table is corrupt.
  def cells(row)
    row.strip.sub(/\A\|/, "").sub(/\|\z/, "").split(/(?<!\\)\|/).map(&:strip)
  end

  def param_row(section, param)
    row = section.lines.find { |line| line.start_with?("| `#{param}` |") }
    raise "no parameter row for `#{param}` in:\n#{section}" if row.nil?

    cells(row)
  end

  def header_cells(section)
    cells(section.lines.find { |line| line.start_with?("| Parameter |") }.to_s)
  end

  def column(section, param, name)
    index = header_cells(section).index(name)
    raise "no `#{name}` column; header is #{header_cells(section).inspect}" if index.nil?

    param_row(section, param)[index]
  end

  around do |example|
    registry.register_extension_tools(action_name => fixture_class_name)
    example.run
  ensure
    registry.extension_tools.delete(action_name)
  end

  let(:section) do
    found = section_for(generate_catalog, action_name)
    expect(found).to be_present, "the generated catalog has no section for #{action_name}"
    found
  end

  it "renders the closed value set an enum declares" do
    expect(column(section, "mode", "Values")).to eq("`alpha`, `beta`, `gamma`")
  end

  it "renders a dash when a parameter declares no closed value set" do
    expect(column(section, "plain", "Values")).to eq("-")
  end

  it "escapes a table separator inside a value so the row keeps its columns" do
    # Unescaped, `a|b` would split the row into an extra cell and every column
    # after it would render shifted — the declaration would be worse than absent.
    expect(column(section, "separator", "Values")).to eq("`a\\|b`, `c`")
    expect(param_row(section, "separator").size).to eq(header_cells(section).size)
  end

  it "escapes a table separator inside a description" do
    expect(column(section, "separator", "Description"))
      .to eq("value containing a table separator \\| character")
  end

  it "renders the element type an array declares" do
    expect(column(section, "tags", "Type")).to eq("array<string>")
    expect(column(section, "records", "Type")).to eq("array<object>")
  end

  it "renders the closed value set an array declares on its ELEMENTS" do
    # The set constrains what may go IN the array; the Type column already reads
    # `array<string>`, so the values are stated unqualified. Rendering `-` here
    # would tell an operator sizing a grant that the wire imposes no closed set,
    # which is exactly false.
    expect(column(section, "scopes", "Values")).to eq("`read`, `write`, `admin`")
  end

  it "renders a closed value set declared on a nested object property" do
    # Qualified by the property it constrains, because the parameter itself is
    # not restricted to those values — only its `record_type` member is.
    expect(column(section, "endpoint", "Values")).to eq("record_type: `A`, `AAAA`, `CNAME`")
  end

  it "renders the element type the WIRE fills in for an array that declares none" do
    # Ai::Tools::ParameterSchema::DEFAULT_ARRAY_ITEMS — the catalog must state
    # the schema the client is handed, not the shorter thing the tool wrote.
    expect(column(section, "untyped_list", "Type")).to eq("array<string>")
  end

  it "keeps every parameter row aligned with the header" do
    rows = section.lines.select { |line| line.start_with?("| `") }
    expect(rows.size).to eq(8)
    rows.each do |row|
      expect(cells(row).size).to eq(header_cells(section).size), "misaligned row: #{row}"
    end
  end

  it "publishes every enum the shared converter puts on the wire" do
    # Derived oracle: the source of truth is ParameterSchema — the same call the
    # tools/list controller and the DB registrar make — not a second reading of
    # the authoring hash here.
    schema = ::Ai::Tools::ParameterSchema.build(
      McpToolCatalogSchemaRenderingFixtureTool.action_definitions[action_name][:parameters]
    )

    enums = schema["properties"].select { |_name, spec| spec["enum"].present? }
    expect(enums.keys).to match_array(%w[mode separator])

    enums.each do |param_name, spec|
      rendered = column(section, param_name, "Values")
      spec["enum"].each do |value|
        expect(rendered).to include(value.to_s.gsub("|", "\\|")),
          "the catalog omits `#{value}` from #{param_name}, which the wire schema constrains it to"
      end
    end
  end
end

RSpec.describe "docs/reference/auto/mcp-tools.md publishes declared enum/items" do
  # The committed artifact, not a regeneration: a generator that renders the
  # value sets but is never regenerated into the tracked file leaves the operator
  # reading the same understated contract.
  def catalog
    @catalog ||= File.read(Rails.root.join("..", "docs", "reference", "auto", "mcp-tools.md"))
  end

  def section_for(action)
    catalog[/^### `#{Regexp.escape(action)}`\n.*?(?=^### |\z)/m]
  end

  it "states the DNS-01 provider slugs the wire constrains the parameter to" do
    section = section_for("system_acme_create_dns_credential")
    expect(section).to be_present

    row = section.lines.find { |line| line.start_with?("| `provider` |") }
    expect(row).to be_present
    # Literal wire values, not the constant they come from: comparing against
    # System::AcmeDnsCredential::SUPPORTED_PROVIDERS would go green over a
    # renderer that emitted the constant's NAME, which is the defect.
    %w[cloudflare route53 gcloud digitalocean hetzner porkbun ovh].each do |slug|
      expect(row).to include("`#{slug}`"),
        "the committed catalog omits the `#{slug}` value from system_acme_create_dns_credential's provider"
    end
  end

  it "states the element set an array parameter's `items` constrains it to" do
    # The residual the first pass of IMP-fb5085178b09 left: a set declared BELOW
    # the parameter published as `-`. Literal slugs, not System::FederationGrant
    # ::SCOPES, for the same reason as the DNS-01 case above.
    section = section_for("system_service_discovery_compose")
    expect(section).to be_present

    row = section.lines.find { |line| line.start_with?("| `grant_scopes` |") }
    expect(row).to be_present
    %w[read write admin migrate].each do |scope|
      expect(row).to include("`#{scope}`"),
        "the committed catalog omits the `#{scope}` element value from system_service_discovery_compose's grant_scopes"
    end
  end

  it "carries a Values column on every parameter table" do
    headers = catalog.lines.select { |line| line.start_with?("| Parameter |") }
    expect(headers).not_to be_empty
    expect(headers.uniq).to eq([ "| Parameter | Type | Required | Values | Description |\n" ])
  end
end
