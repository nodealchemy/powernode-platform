# frozen_string_literal: true

require "rails_helper"

# IMP-7e84ae0ccc91 — the one-line summary tools/list carries per tool, and the
# builder shared by tools/list, platform.describe_tool and the legacy
# tools/describe path.
RSpec.describe Mcp::ToolCatalog do
  describe ".summarize" do
    it "keeps a short single-sentence description whole and reports nothing lost" do
      expect(described_class.summarize("List agents.", limit: 160)).to eq(["List agents.", false])
    end

    it "keeps the first sentence only and reports the rest as lost" do
      text = "Deploy a module to the fleet. GATED: parks behind an approval. Side effects: restarts rails."
      expect(described_class.summarize(text, limit: 160)).to eq(["Deploy a module to the fleet.", true])
    end

    it "does not split on an abbreviation followed by a lower-case continuation" do
      text = "Filter by kind, e.g. gitea or github, before listing."
      expect(described_class.summarize(text, limit: 160)).to eq([text, false])
    end

    it "collapses newlines and runs of whitespace into single spaces" do
      text = "Return the\n  full   entry.\nMore."
      expect(described_class.summarize(text, limit: 160)).to eq(["Return the full entry.", true])
    end

    it "cuts a long first sentence at a word boundary with an ellipsis, within the cap" do
      text = "Provision an instance " + ("with a very long clause " * 20) + "at the end."
      summary, truncated = described_class.summarize(text, limit: 60)

      expect(truncated).to be(true)
      expect(summary.length).to be <= 60
      expect(summary).to end_with(described_class::ELLIPSIS)
      # Word boundary: the text before the ellipsis is a prefix of the source
      # ending on a whole word, never mid-word.
      head = summary.delete_suffix(described_class::ELLIPSIS)
      expect(text).to start_with(head)
      expect(text[head.length]).to eq(" ")
    end

    it "strips a dangling separator before the ellipsis" do
      text = "Alpha beta, " + ("gamma " * 40)
      summary, = described_class.summarize(text, limit: 13)
      expect(summary).to eq("Alpha beta…")
    end

    it "returns an empty, untruncated summary for a blank description" do
      expect(described_class.summarize(nil, limit: 160)).to eq(["", false])
      expect(described_class.summarize("   ", limit: 160)).to eq(["", false])
    end

    it "never exceeds the cap on the real registry" do
      limit = described_class.list_description_limit
      long = ::Ai::Tools::PlatformApiToolRegistry.tool_definitions.map { |d| d[:description].to_s }
      expect(long.count { |d| d.length > limit }).to be > 0 # otherwise vacuous
      long.each do |text|
        summary, = described_class.summarize(text, limit: limit)
        expect(summary.length).to be <= limit
      end
    end
  end

  describe ".list_description_limit" do
    it "falls back to the constant when nothing is configured" do
      expect(described_class.list_description_limit).to eq(described_class::LIST_DESCRIPTION_LIMIT)
    end

    it "honours a positive SiteSetting and ignores a non-positive one" do
      allow(::SiteSetting).to receive(:get).with(described_class::LIST_DESCRIPTION_LIMIT_SETTING).and_return(80)
      expect(described_class.list_description_limit).to eq(80)

      allow(::SiteSetting).to receive(:get).with(described_class::LIST_DESCRIPTION_LIMIT_SETTING).and_return(0)
      expect(described_class.list_description_limit).to eq(described_class::LIST_DESCRIPTION_LIMIT)
    end
  end

  describe "#list_entries / #describe / #nearest" do
    before do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [
          { name: "list_agents", description: "List agents. Long tail that the listing drops.", parameters: {} },
          { name: "create_agent", description: "Create an agent.", parameters: { name: { type: "string", required: true } } }
        ]
      )
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
                 [{ id: "platform.health", description: "Health.", input_schema: { "type" => "object" } }])
    end

    let(:catalog) { described_class.new(protocol_version: "2025-11-25") }

    it "lists one line per tool, name-sorted, with version-gated metadata" do
      names = catalog.list_entries.map { |t| t["name"] }
      expect(names).to eq(%w[platform.create_agent platform.health platform.list_agents])

      listed = catalog.list_entries.find { |t| t["name"] == "platform.list_agents" }
      expect(listed["description"]).to eq("List agents.")
      expect(listed["annotations"]).to eq({ "readOnlyHint" => true })
      expect(listed["title"]).to eq("List Agents")
      expect(listed["outputSchema"]["required"]).to eq(["success"])
    end

    it "describes with the full text, the summary and the truncated flag" do
      detail = catalog.describe("platform.list_agents")
      expect(detail["description"]).to eq("List agents. Long tail that the listing drops.")
      expect(detail["summary"]).to eq("List agents.")
      expect(detail["truncated"]).to be(true)
      expect(detail["inputSchema"]).to eq(catalog.list_entries.find { |t| t["name"] == "platform.list_agents" }["inputSchema"])

      expect(catalog.describe("platform.create_agent")["truncated"]).to be(false)
      expect(catalog.describe("platform.health")["outputSchema"]).to eq({ "type" => "object" })
      expect(catalog.describe("platform.nope")).to be_nil
    end

    it "keeps the legacy shape for a 2024-11-05 revision" do
      legacy = described_class.new(protocol_version: "2024-11-05").list_entries.first
      expect(legacy.keys).to contain_exactly("name", "description", "inputSchema")
    end

    it "applies a restricted principal's grant filter" do
      principal = instance_double(Mcp::Principal)
      allow(principal).to receive(:filter_tools) { |tools| tools.select { |t| t["name"] == "platform.health" } }

      names = described_class.new(protocol_version: "2025-11-25", principal: principal).list_entries.map { |t| t["name"] }
      expect(names).to eq(["platform.health"])
    end

    it "finds the nearest names by prefix, then substring, with or without the platform. prefix" do
      expect(catalog.nearest("platform.list_agent")).to eq(["platform.list_agents"])
      expect(catalog.nearest("agent")).to contain_exactly("platform.create_agent", "platform.list_agents")
      expect(catalog.nearest("zzz")).to eq([])
      expect(catalog.nearest("")).to eq([])
    end

    it "scopes #describe and #nearest to a restricted principal's grant" do
      principal = instance_double(Mcp::Principal)
      # Mirrors Mcp::Principal#filter_tools, which accepts entry hashes AND
      # bare names (#tool_name_of) — the name-only path is what #nearest and
      # the single-entry #describe lookup use.
      allow(principal).to receive(:filter_tools) do |tools|
        tools.select { |t| (t.is_a?(Hash) ? t["name"] : t) == "platform.health" }
      end
      scoped = described_class.new(protocol_version: "2025-11-25", principal: principal)

      expect(scoped.describe("platform.health")).not_to be_nil
      expect(scoped.describe("platform.list_agents")).to be_nil
      expect(scoped.nearest("agent")).to eq([])
    end
  end

  # IMP-7e84ae0ccc91 review: platform.describe_tool must not be a door around
  # Mcp::Principal's default-deny. A restricted (instance / federation)
  # principal that was granted this ONE verb must still see only its granted
  # subset — neither the full entry of an ungranted tool nor its name through
  # the nearest-match list.
  describe Ai::Tools::ToolCatalogTool do
    before do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [
          { name: "describe_tool", description: "Describe one tool.", parameters: {} },
          { name: "list_agents", description: "List agents. Long tail.", parameters: {} },
          { name: "system_sdwan_get_topology", description: "Topology. Long tail.", parameters: {} }
        ]
      )
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
      ::Mcp::Principal.tool_grant_resolver = ->(_instance) { ["platform.describe_tool", "platform.list_agents"] }
    end

    after { ::Mcp::Principal.reset! }

    let(:node_instance) { double("NodeInstance", id: "11111111-1111-7111-8111-111111111111") }

    def tool_for(instance_principal:)
      tool = described_class.new(account: nil, user: nil, agent: nil)
      if instance_principal
        tool.node_instance = node_instance
        tool.instance_authorized = true
      end
      tool
    end

    it "describes a granted tool for an instance principal" do
      result = tool_for(instance_principal: true).send(:call, name: "platform.list_agents")

      expect(result[:success]).to be(true)
      expect(result[:data]["description"]).to eq("List agents. Long tail.")
    end

    it "refuses an UNGRANTED tool for an instance principal and does not name it" do
      result = tool_for(instance_principal: true).send(:call, name: "platform.system_sdwan_get_topology")

      expect(result[:success]).to be(false)
      expect(result[:nearest_matches]).to eq([])
    end

    it "does not leak ungranted names through the nearest-match list" do
      result = tool_for(instance_principal: true).send(:call, name: "platform.system_sdwan")

      expect(result[:success]).to be(false)
      expect(result[:nearest_matches]).to eq([])
    end

    it "fails closed for a restricted principal whose grant cannot be resolved" do
      tool = described_class.new(account: nil, user: nil, agent: nil)
      tool.instance_authorized = true # federation principal: no node_instance to scope with

      result = tool.send(:call, name: "platform.list_agents")

      expect(result[:success]).to be(false)
    end

    it "still serves the full catalog to a user principal" do
      result = tool_for(instance_principal: false).send(:call, name: "platform.system_sdwan_get_topology")

      expect(result[:success]).to be(true)
      expect(result[:data]["name"]).to eq("platform.system_sdwan_get_topology")
    end

    it "keeps its own listed summary self-contained under the cap" do
      summary, = ::Mcp::ToolCatalog.summarize(described_class.definition[:description])

      expect(summary.length).to be <= ::Mcp::ToolCatalog.list_description_limit
      expect(summary).not_to end_with(::Mcp::ToolCatalog::ELLIPSIS)
      expect(summary.count("(")).to eq(summary.count(")"))
    end
  end
end
