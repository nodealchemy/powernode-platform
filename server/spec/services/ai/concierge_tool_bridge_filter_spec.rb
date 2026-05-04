# frozen_string_literal: true

require "rails_helper"

# Tests the metadata-driven tool filter added to ConciergeToolBridge in Phase
# 10.3. Extension agents (e.g. System Concierge) declare their tool surface via
# `agent.metadata["concierge_tool_filter"]` to restrict the LLM to a curated
# slice instead of the platform's ~84 general-purpose tools.
RSpec.describe Ai::ConciergeToolBridge do
  let(:account) { create(:account) }
  let(:user) { account.users.first || create(:user, account: account) }
  let(:provider) { ::Ai::Provider.first || create(:ai_provider) }
  let(:conversation) do
    instance_double(::Ai::Conversation, workspace_conversation?: false)
  end

  def build_bridge(metadata: {})
    agent = ::Ai::Agent.create!(
      account: account, name: "Test Agent #{SecureRandom.hex(4)}",
      agent_type: "assistant", status: "active",
      creator: user, provider: provider,
      metadata: metadata
    )
    described_class.new(
      agent: agent, account: account, conversation: conversation, user: user
    )
  end

  def stub_registry_with(tool_names)
    definitions = tool_names.map do |n|
      { name: n, description: "test", parameters: { type: "object", properties: {} } }
    end
    allow(::Ai::Tools::PlatformApiToolRegistry)
      .to receive(:tool_definitions).and_return(definitions)
  end

  describe "#build_tool_definitions" do
    it "returns the full tool surface (minus self-referential excludes) when no filter is set" do
      stub_registry_with(%w[list_agents execute_agent system_list_nodes system_sdwan_list_networks])
      bridge = build_bridge

      tool_names = bridge.send(:build_tool_definitions).map { |t| t[:name] || t["name"] }

      expect(tool_names).to include("list_agents", "execute_agent",
                                     "system_list_nodes", "system_sdwan_list_networks",
                                     "request_confirmation")
    end

    it "filters to tools matching prefix patterns when concierge_tool_filter is set" do
      stub_registry_with(%w[list_agents execute_agent system_list_nodes system_sdwan_list_networks
                            create_team trigger_pipeline])
      bridge = build_bridge(metadata: { "concierge_tool_filter" => [ "system_*" ] })

      tool_names = bridge.send(:build_tool_definitions).map { |t| t[:name] || t["name"] }

      expect(tool_names).to include("system_list_nodes", "system_sdwan_list_networks",
                                     "request_confirmation")
      expect(tool_names).not_to include("list_agents", "execute_agent",
                                          "create_team", "trigger_pipeline")
    end

    it "supports exact tool-name patterns alongside prefixes" do
      stub_registry_with(%w[list_agents execute_agent search_knowledge system_list_nodes])
      bridge = build_bridge(
        metadata: { "concierge_tool_filter" => [ "system_*", "search_knowledge" ] }
      )

      tool_names = bridge.send(:build_tool_definitions).map { |t| t[:name] || t["name"] }

      expect(tool_names).to include("system_list_nodes", "search_knowledge")
      expect(tool_names).not_to include("list_agents", "execute_agent")
    end

    it "always appends the request_confirmation virtual tool regardless of filter" do
      stub_registry_with(%w[system_list_nodes])
      bridge = build_bridge(metadata: { "concierge_tool_filter" => [ "system_*" ] })

      tool_names = bridge.send(:build_tool_definitions).map { |t| t[:name] || t["name"] }

      expect(tool_names).to include("request_confirmation")
    end

    it "treats empty / non-array filter as no filter" do
      stub_registry_with(%w[list_agents system_list_nodes])
      bridge = build_bridge(metadata: { "concierge_tool_filter" => [] })

      tool_names = bridge.send(:build_tool_definitions).map { |t| t[:name] || t["name"] }

      expect(tool_names).to include("list_agents", "system_list_nodes")
    end

    it "tolerates default empty-hash metadata (schema enforces NOT NULL with {} default)" do
      stub_registry_with(%w[system_list_nodes])
      bridge = build_bridge(metadata: {})

      expect { bridge.send(:build_tool_definitions) }.not_to raise_error
    end
  end
end
