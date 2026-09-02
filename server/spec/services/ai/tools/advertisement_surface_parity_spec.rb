# frozen_string_literal: true

require "rails_helper"

# IMP-5039d026da0d — `.permitted?` / `.action_advertised?` gated exactly ONE of
# the four surfaces that advertise platform tools.
#
# `Ai::Tools::PlatformApiToolRegistry.available_tools` (the MCP tools/list path)
# consults both predicates. The other three walked
# `PlatformApiToolRegistry.all_tools` directly and consulted neither:
#
#   * Ai::Tools::McpPlatformToolRegistrar.sync_to_database! — writes the
#     `mcp_tools` rows behind the frontend MCP browser.
#   * Ai::Tools::McpPlatformToolRegistrar.register_all! (via .tool_classes) —
#     publishes one manifest per tool class into Mcp::RegistryService.
#   * Ai::Tools::SemanticToolDiscoveryService#collect_all_tools — feeds the
#     embedding index behind discovery-by-description.
#
# Concretely: after IMP-2836d290f99a (5d4bcabc4) the four docker-runtime actions
# are correctly absent from tools/list in core mode, yet were still present in
# the DB-backed catalog the frontend browses and still embedded in the semantic
# discovery index — so an agent doing discovery-by-embedding could be steered
# toward an action that is not offered and cannot run.
#
# The oracle is PARITY, not a spot check: whatever `available_tools` drops, the
# other three must drop as well.
#
# Fixtures are defined at file scope (a constant assigned inside an RSpec block
# lands on Object, where a same-named constant in another spec file can clobber
# it) and named distinctively for the same reason. They carry no
# REQUIRED_PERMISSION and no ACTION_PERMISSIONS, so the namespace-wide sweep in
# tool_permission_catalog_guard_spec.rb picks up nothing from them.

# Stands in for a core-hosted, extension-BACKED tool whose extension is absent —
# the Ai::Tools::DockerProvisioningTool shape, where the whole class is gated.
class ZzAdvertisementParityUnavailableTool < Ai::Tools::BaseTool
  ACTION = "zz_advertisement_parity_unavailable"

  def self.permitted?(agent:)
    false
  end

  def self.definition
    { name: ACTION, description: "Fixture: every action depends on an absent extension.", parameters: {} }
  end

  def self.action_definitions
    { ACTION => { description: "Fixture action that cannot run.", parameters: {} } }
  end
end

# Stands in for a MIXED tool — the Ai::Tools::DiskImageOperatorTool shape, where
# only some actions depend on the absent extension, so the gate is per-ACTION.
class ZzAdvertisementParityMixedTool < Ai::Tools::BaseTool
  HIDDEN_ACTION = "zz_advertisement_parity_hidden"
  VISIBLE_ACTION = "zz_advertisement_parity_visible"

  def self.action_advertised?(action_name)
    action_name.to_s != HIDDEN_ACTION
  end

  def self.definition
    { name: "zz_advertisement_parity_mixed", description: "Fixture: one core action, one extension-backed action.", parameters: {} }
  end

  def self.action_definitions
    {
      HIDDEN_ACTION => { description: "Fixture action backed by an absent extension.", parameters: {} },
      VISIBLE_ACTION => { description: "Fixture action that runs on core alone.", parameters: {} }
    }
  end
end

RSpec.describe "tool advertisement surface parity" do
  let(:account) { create(:account) }
  let!(:mcp_server) { create(:mcp_server, account: account, name: "Powernode MCP") }

  let(:unavailable_action) { ZzAdvertisementParityUnavailableTool::ACTION }
  let(:hidden_action) { ZzAdvertisementParityMixedTool::HIDDEN_ACTION }
  let(:visible_action) { ZzAdvertisementParityMixedTool::VISIBLE_ACTION }

  # A controlled registry, so the assertions are about the FILTER and not about
  # whichever extensions happen to be loaded in this bundle. Stubbing .all_tools
  # covers every surface under test: all four read it (directly, or through
  # .available_tools / .tool_classes, which are self-calls on the registry).
  let(:stubbed_registry) do
    {
      unavailable_action => "ZzAdvertisementParityUnavailableTool",
      hidden_action => "ZzAdvertisementParityMixedTool",
      visible_action => "ZzAdvertisementParityMixedTool"
    }
  end

  before do
    allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_return(stubbed_registry)
    Ai::Tools::McpPlatformToolRegistrar.instance_variable_set(:@tool_classes, nil)
  end

  after do
    Ai::Tools::McpPlatformToolRegistrar.instance_variable_set(:@tool_classes, nil)
  end

  # Oracle guard. Every assertion below is stated as "matches available_tools",
  # so a broken available_tools would make the whole file vacuous.
  describe "Ai::Tools::PlatformApiToolRegistry.available_tools (the reference surface)" do
    it "drops the unpermitted class and the unadvertised action, and keeps the core one" do
      names = Ai::Tools::PlatformApiToolRegistry.available_tools.keys

      expect(names).to contain_exactly(visible_action)
    end
  end

  describe "Ai::Tools::McpPlatformToolRegistrar.sync_to_database!" do
    it "writes no mcp_tools row for an action available_tools refuses to advertise" do
      Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)

      written = mcp_server.reload.mcp_tools.pluck(:name)

      expect(written).to include(visible_action)
      expect(written).not_to include(unavailable_action)
      expect(written).not_to include(hidden_action)
    end

    it "reports a count that matches what it wrote" do
      count = Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)

      expect(count).to eq(mcp_server.reload.mcp_tools.count)
    end

    # The MIGRATION half. Filtering the write only de-advertises on a FRESH
    # database; on an existing one the row is already there and it is the stale
    # sweep at the bottom of sync_to_database! that removes it. Both examples
    # below pre-create that row, which no other example in this file does.
    context "on an EXISTING database that already carries the de-advertised row" do
      let!(:stale_row) do
        create(:mcp_tool, mcp_server: mcp_server, name: unavailable_action,
                          description: "written before the extension went away")
      end

      it "removes it" do
        Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)

        expect(mcp_server.reload.mcp_tools.pluck(:name)).not_to include(unavailable_action)
      end

      # Regression oracle for the FK hazard the filter made reachable:
      # mcp_tool_executions has a NO-ACTION foreign key on mcp_tools, so a
      # relation#delete_all here raises ActiveRecord::InvalidForeignKey for any
      # row that has ever been executed and aborts the entire catalog sync —
      # including the rows the sweep had nothing to do with.
      it "removes it even when it carries execution history, without raising" do
        user = create(:user, account: account)
        create(:mcp_tool_execution, mcp_tool: stale_row, user: user)

        expect { Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account) }
          .not_to raise_error

        expect(mcp_server.reload.mcp_tools.pluck(:name)).not_to include(unavailable_action)
        expect(McpToolExecution.where(mcp_tool_id: stale_row.id).count).to eq(0)
      end
    end
  end

  describe "Ai::Tools::McpPlatformToolRegistrar.register_all!" do
    it "publishes no manifest for a tool class available_tools refuses to advertise" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)

      published = []
      allow(registry).to receive(:register_tool) { |tool_id, _manifest| published << tool_id }

      Ai::Tools::McpPlatformToolRegistrar.register_all!(account: account)

      expect(published).to include("platform.zz_advertisement_parity_mixed")
      expect(published).not_to include("platform.#{unavailable_action}")
    end

    it "leaves .tool_classes — the tools/call RESOLUTION set — unfiltered" do
      # Advertisement and invocability are separate questions: a client holding a
      # stale catalog must still resolve to the tool class so it gets the tool's
      # own refusal envelope rather than "Unknown platform tool".
      expect(Ai::Tools::McpPlatformToolRegistrar.send(:tool_classes))
        .to include(ZzAdvertisementParityUnavailableTool)
      expect(Ai::Tools::McpPlatformToolRegistrar.send(:find_tool_class, unavailable_action))
        .to eq(ZzAdvertisementParityUnavailableTool)
    end
  end

  # The finding's concrete subject, on the REAL classes rather than fixtures:
  # after IMP-2836d290f99a the four docker-runtime actions left tools/list in
  # core mode and stayed in the DB catalog and the discovery index. Core mode is
  # simulated by stubbing the classes' own `.extension_available?` probe (the
  # bundle under test loads extensions/system, so `defined?(::System)` is true
  # here); the registry is still stubbed down to three entries so the real
  # ~600-action sync does not run on the shared test database.
  describe "the extension-backed tools this finding was raised about" do
    let(:stubbed_registry) do
      {
        "system_provision_docker_runtime" => "Ai::Tools::DockerProvisioningTool",
        "provision_disk_image_webhook" => "Ai::Tools::DiskImageOperatorTool",
        "provision_ci_worker" => "Ai::Tools::DiskImageOperatorTool"
      }
    end

    before do
      allow(Ai::Tools::DockerProvisioningTool).to receive(:extension_available?).and_return(false)
      allow(Ai::Tools::DiskImageOperatorTool).to receive(:extension_available?).and_return(false)
    end

    it "drops them from tools/list, keeping the core-only action" do
      expect(Ai::Tools::PlatformApiToolRegistry.available_tools.keys)
        .to contain_exactly("provision_ci_worker")
    end

    it "drops them from the mcp_tools rows the frontend MCP browser lists" do
      Ai::Tools::McpPlatformToolRegistrar.sync_to_database!(account: account)
      written = mcp_server.reload.mcp_tools.pluck(:name)

      expect(written).to include("provision_ci_worker")
      expect(written).not_to include("system_provision_docker_runtime")
      expect(written).not_to include("provision_disk_image_webhook")
    end

    it "drops them from the semantic discovery index" do
      names = Ai::Tools::SemanticToolDiscoveryService.new(account: account)
                                                     .send(:collect_all_tools)
                                                     .select { |t| t[:source] == "platform" }
                                                     .map { |t| t[:name] }

      expect(names).to contain_exactly("provision_ci_worker")
    end

    it "keeps the mixed class's manifest, since one of its actions is core-only" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)

      published = []
      allow(registry).to receive(:register_tool) { |tool_id, _manifest| published << tool_id }

      Ai::Tools::McpPlatformToolRegistrar.register_all!(account: account)

      expect(published).to contain_exactly("platform.disk_image_operator")
    end
  end

  describe "Ai::Tools::SemanticToolDiscoveryService#collect_all_tools" do
    it "does not embed an action available_tools refuses to advertise" do
      service = Ai::Tools::SemanticToolDiscoveryService.new(account: account)

      platform_names = service.send(:collect_all_tools)
                              .select { |t| t[:source] == "platform" }
                              .map { |t| t[:name] }

      expect(platform_names).to contain_exactly(visible_action)
    end
  end
end
