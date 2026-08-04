# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PlatformApiToolRegistry do
  let(:account) { create(:account) }

  describe "::TOOLS" do
    it "is a frozen hash" do
      expect(described_class::TOOLS).to be_frozen
    end

    it "maps tool names to class name strings" do
      described_class::TOOLS.each do |name, class_name|
        expect(name).to be_a(String)
        expect(class_name).to be_a(String)
        expect { class_name.constantize }.not_to raise_error
      end
    end

    it "includes expected tool entries" do
      expect(described_class::TOOLS).to include(
        "create_agent" => "Ai::Tools::AgentManagementTool",
        "list_agents" => "Ai::Tools::AgentManagementTool",
        "create_team" => "Ai::Tools::TeamManagementTool",
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "query_knowledge_base" => "Ai::Tools::KnowledgeTool",
        "get_api_reference" => "Ai::Tools::ApiReferenceTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool"
      )
    end

    it "registers the SystemFleetTool provider CRUD actions" do
      expect(described_class::TOOLS).to include(
        "system_create_provider" => "Ai::Tools::SystemFleetTool",
        "system_delete_provider" => "Ai::Tools::SystemFleetTool"
      )
    end

    # Audit F4-08 — instance start/stop/reboot were absent from the MCP
    # surface despite full InstanceControlService + AASM support.
    it "registers the SystemFleetTool instance control actions" do
      expect(described_class::TOOLS).to include(
        "system_start_instance" => "Ai::Tools::SystemFleetTool",
        "system_stop_instance" => "Ai::Tools::SystemFleetTool",
        "system_reboot_instance" => "Ai::Tools::SystemFleetTool"
      )
    end

    it "registers the SystemFleetTool observability and runbook actions" do
      expect(described_class::TOOLS).to include(
        "system_module_diff" => "Ai::Tools::SystemFleetTool",
        "system_compliance_snapshot" => "Ai::Tools::SystemFleetTool",
        "system_runbook_generate" => "Ai::Tools::SystemFleetTool",
        "system_cve_runbook_generate" => "Ai::Tools::SystemFleetTool",
        "system_cve_triage" => "Ai::Tools::SystemFleetTool",
        "system_recent_signals" => "Ai::Tools::SystemFleetTool",
        "system_attribute_failure" => "Ai::Tools::SystemFleetTool",
        "system_inspect_correlation" => "Ai::Tools::SystemFleetTool"
      )
    end

    # IMP-b2f80e6d1c65 — these five had an ACTION_PERMISSIONS entry and a
    # dispatch branch in system_fleet_tool.rb, but no registry key, so they
    # were reachable ONLY by smuggling the action into another tool's name
    # (closed by e6c3e6e4d). Same "declared but unroutable" shape
    # system_upgrade_boot_image was previously in.
    it "registers the SystemFleetTool ops-hold and publish-target actions" do
      expect(described_class::TOOLS).to include(
        "system_instance_hold" => "Ai::Tools::SystemFleetTool",
        "system_instance_hold_status" => "Ai::Tools::SystemFleetTool",
        "system_instance_release_hold" => "Ai::Tools::SystemFleetTool",
        "system_module_publish_target" => "Ai::Tools::SystemFleetTool",
        "system_module_publication_integrity" => "Ai::Tools::SystemFleetTool"
      )
    end
  end

  describe ".available_tools" do
    it "returns a hash of tool name to class" do
      tools = described_class.available_tools
      expect(tools).to be_a(Hash)
      tools.each do |name, klass|
        expect(name).to be_a(String)
        expect(klass).to be < Ai::Tools::BaseTool
      end
    end

    it "filters by agent permission when agent provided" do
      agent = create(:ai_agent, account: account)
      tools = described_class.available_tools(agent: agent)
      expect(tools).to be_a(Hash)
    end

    it "handles NameError for unavailable tool classes" do
      allow(Rails.logger).to receive(:warn)
      # Inject a broken entry at the seam available_tools actually iterates
      # (all_tools = static TOOLS + extension-registered tools). Stubbing the
      # frozen TOOLS constant alone no longer isolates the case in full mode,
      # where extension tools are also present.
      allow(described_class).to receive(:all_tools).and_return({ "broken" => "Nonexistent::Tool" })

      tools = described_class.available_tools
      expect(tools).to eq({})
    end
  end

  describe ".find_tool" do
    it "returns the tool class for a known static tool" do
      klass = described_class.find_tool("create_agent")
      expect(klass).to eq(Ai::Tools::AgentManagementTool)
    end

    it "returns nil for an unknown tool" do
      klass = described_class.find_tool("nonexistent_tool")
      expect(klass).to be_nil
    end
  end

  describe ".tool_definitions" do
    it "returns an array of tool definitions with names" do
      definitions = described_class.tool_definitions
      expect(definitions).to be_an(Array)
      definitions.each do |defn|
        expect(defn).to have_key(:name)
        expect(defn).to have_key(:description)
        expect(defn).to have_key(:parameters)
      end
    end
  end

  describe ".discover_tools" do
    it "delegates to SemanticToolDiscoveryService" do
      service = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).with(account: account).and_return(service)
      allow(service).to receive(:discover).with(query: "deploy", capabilities: nil, limit: 10).and_return([])

      result = described_class.discover_tools(query: "deploy", account: account)
      expect(result).to eq([])
    end

    it "passes capabilities and limit" do
      service = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).with(account: account).and_return(service)
      allow(service).to receive(:discover).with(query: "test", capabilities: ["ci"], limit: 5).and_return([])

      described_class.discover_tools(query: "test", account: account, capabilities: ["ci"], limit: 5)
      expect(service).to have_received(:discover).with(query: "test", capabilities: ["ci"], limit: 5)
    end
  end

  describe ".register_dynamic_tool" do
    it "delegates to SemanticToolDiscoveryService" do
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:register_dynamic_tool).and_return({ id: "dynamic.test" })

      result = described_class.register_dynamic_tool(
        account: account, name: "test", description: "Test tool",
        parameters: {}, handler: "Ai::Tools::BaseTool"
      )
      expect(result[:id]).to eq("dynamic.test")
    end
  end

  describe ".unregister_dynamic_tool" do
    it "delegates to SemanticToolDiscoveryService" do
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:unregister_dynamic_tool)

      described_class.unregister_dynamic_tool(account: account, name: "test")
      expect(Ai::Tools::SemanticToolDiscoveryService).to have_received(:unregister_dynamic_tool).with(account: account, name: "test")
    end
  end

  describe ".dynamic_tools" do
    it "returns empty array when no account" do
      expect(described_class.dynamic_tools(account: nil)).to eq([])
    end

    it "reads from cache for the account" do
      cached = [{ name: "custom_tool", description: "Custom" }]
      allow(Rails.cache).to receive(:read).with("tool_discovery:#{account.id}:dynamic_tools").and_return(cached)

      result = described_class.dynamic_tools(account: account)
      expect(result).to eq(cached)
    end

    it "returns empty array when cache is empty" do
      allow(Rails.cache).to receive(:read).with("tool_discovery:#{account.id}:dynamic_tools").and_return(nil)

      result = described_class.dynamic_tools(account: account)
      expect(result).to eq([])
    end
  end

  describe "registration coverage (no built-but-unrouted actions)" do
    # Tool classes are enumerated from DISK, not from the registry's own values.
    #
    # An earlier version iterated `all_tools.values.uniq`, i.e. only classes
    # ALREADY registered for at least one action — so a tool class registered
    # for NONE was invisible to this guard entirely. SystemFleetTool's
    # system_upgrade_boot_image (declared, permission-mapped, dispatched and
    # ~20 specs deep, yet unroutable) was caught only because that class
    # happened to have other actions mapped. A wholly-unregistered class would
    # have sailed through.
    def tool_class_names
      (
        Dir.glob(Rails.root.join("app/services/ai/tools/*_tool.rb")) +
        Dir.glob(Rails.root.join("../extensions/*/server/app/services/ai/tools/*_tool.rb")) +
        Dir.glob(Rails.root.join("../extensions/private/*/server/app/services/ai/tools/*_tool.rb"))
      ).map { |f| "Ai::Tools::#{File.basename(f, '.rb').camelize}" }.uniq.sort
    end

    # Floor for classes actually inspected. Every rescue below (absent
    # extension, abstract base) silently shrinks coverage, so without this the
    # guard can degrade to vacuously green — e.g. if autoloading broke and
    # every constantize raised. 64 declare actions on a full dev checkout;
    # this sits well under that so a core-only or extension-less environment
    # still passes, while a collapse to near-zero fails loudly.
    MIN_INSPECTED_TOOL_CLASSES = 40

    it "registers every action that each loaded tool declares" do
      registry_keys = described_class.all_tools.keys.map(&:to_s)
      registered_classes = described_class.all_tools.values.uniq.to_set

      inspected = 0
      unrouted = {}
      unregistered = []

      tool_class_names.each do |class_name|
        klass =
          begin
            class_name.constantize
          rescue NameError, LoadError
            next # extension tool class not present in this environment
          end
        next unless klass.respond_to?(:action_definitions)

        actions =
          begin
            klass.action_definitions.keys.map(&:to_s)
          rescue NotImplementedError, StandardError
            next # abstract base class (BaseTool) — not introspectable
          end
        next if actions.empty?

        inspected += 1
        unregistered << class_name unless registered_classes.include?(class_name)
        missing = actions - registry_keys
        unrouted[class_name] = missing if missing.any?
      end

      expect(inspected).to be >= MIN_INSPECTED_TOOL_CLASSES,
        "only inspected #{inspected} tool classes (floor #{MIN_INSPECTED_TOOL_CLASSES}) — " \
        "this guard has degraded toward vacuous; check autoloading before trusting a green run"

      expect(unregistered).to be_empty,
        "tool classes declare MCP actions but appear nowhere in PlatformApiToolRegistry " \
        "(every action they expose is unreachable): #{unregistered.inspect}"

      expect(unrouted).to be_empty,
        "tool classes declare MCP actions absent from PlatformApiToolRegistry (unreachable): #{unrouted.inspect}"
    end
  end
end
