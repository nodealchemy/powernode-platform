# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Discovery::McpScannerService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  # The scanner no longer references the business-only Mcp::HostedServer constant.
  # It resolves the server source via Powernode::ExtensionRegistry.provider(:mcp_hosted_servers),
  # so these specs stub that seam (the registry lookup) rather than a model constant —
  # which is exactly how the decoupling keeps core free of business model references.
  describe '#scan' do
    context 'when no mcp_hosted_servers provider is registered (core mode)' do
      before do
        allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
        allow(Powernode::ExtensionRegistry).to receive(:provider).with(:mcp_hosted_servers).and_return(nil)
      end

      it 'returns agents and empty tools/connections' do
        create(:ai_agent, account: account)

        result = service.scan

        expect(result[:agents]).to be_an(Array)
        expect(result[:tools]).to be_empty
        expect(result[:connections]).to be_empty
      end
    end

    context 'with an mcp_hosted_servers provider supplying servers' do
      let(:agent) { create(:ai_agent, account: account) }
      let(:server) do
        double('hosted_server',
          id: SecureRandom.uuid,
          name: "Tool Server",
          tool_manifest: {
            "tools" => [
              { "name" => "code_search", "description" => "Search code repositories" },
              { "name" => "deploy_app", "description" => "Deploy application to production" }
            ]
          }
        )
      end
      let(:servers_relation) { double('servers_relation') }
      let(:source) { double('McpHostedServerSource') }

      before do
        allow(server).to receive(:respond_to?).with(:tool_manifest).and_return(true)
        allow(servers_relation).to receive(:each).and_yield(server)
        allow(source).to receive(:for_account).with(account).and_return(servers_relation)
        allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
        allow(Powernode::ExtensionRegistry).to receive(:provider).with(:mcp_hosted_servers).and_return(source)
      end

      it 'extracts tools from servers' do
        result = service.scan

        expect(result[:tools].size).to eq(2)
        expect(result[:tools].first[:name]).to eq("code_search")
        expect(result[:tools].first[:server_name]).to eq("Tool Server")
      end

      it 'builds agent nodes' do
        agent # ensure created before scan
        result = service.scan

        agent_node = result[:agents].find { |a| a[:id] == agent.id }
        expect(agent_node).to be_present
        expect(agent_node[:type]).to eq("agent")
      end
    end
  end

  describe '#match_tools_to_agents' do
    let(:tools) do
      [
        { name: "code_search", description: "Search through code repositories" },
        { name: "deploy_service", description: "Deploy a service to production" },
        { name: "analyze_data", description: "Analyze data sets and generate reports" }
      ]
    end

    context 'when agent has matching skills' do
      # The service checks respond_to?(:ai_agent_skills) but calls agent.agent_skills.
      # Use a plain double to avoid the "does not implement" error.
      let(:agent) do
        double('agent',
          id: SecureRandom.uuid,
          name: "Code Agent",
          description: "Agent for code tasks",
          status: "active",
          created_at: Time.current
        ).tap do |a|
          allow(a).to receive(:respond_to?).and_return(false)
          allow(a).to receive(:respond_to?).with(:ai_agent_skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)
          allow(a).to receive(:respond_to?).with(:status).and_return(true)
          allow(a).to receive(:respond_to?).with(:provider).and_return(false)
          allow(a).to receive(:respond_to?).with(:model).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:agent_skills).and_return(skill_relation)
          allow(skill_relation).to receive(:pluck).with(:name).and_return([ "code", "search" ])
        end
      end

      it 'returns matches with confidence scores' do
        agents_relation = double('agents_relation')
        allow(agents_relation).to receive(:find_each).and_yield(agent)

        matches = service.match_tools_to_agents(tools, agents_relation)

        expect(matches.size).to eq(1)
        expect(matches.first[:agent_id]).to eq(agent.id)
        expect(matches.first[:confidence]).to be_between(0.0, 1.0)
        expect(matches.first[:matched_tools]).to include("code_search")
      end
    end

    context 'when agent has no matching skills' do
      let(:agent) do
        double('agent',
          id: SecureRandom.uuid,
          name: "Other Agent",
          description: "Agent for other tasks"
        ).tap do |a|
          allow(a).to receive(:respond_to?).and_return(false)
          allow(a).to receive(:respond_to?).with(:ai_agent_skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:agent_skills).and_return(skill_relation)
          allow(skill_relation).to receive(:pluck).with(:name).and_return([ "unrelated_skill" ])
        end
      end

      it 'returns empty matches' do
        agents_relation = double('agents_relation')
        allow(agents_relation).to receive(:find_each).and_yield(agent)

        matches = service.match_tools_to_agents(tools, agents_relation)
        expect(matches).to be_empty
      end
    end

    context 'when agent has no skills at all' do
      let(:agent) do
        double('agent',
          id: SecureRandom.uuid,
          name: "Skillless Agent",
          description: "Agent without skills"
        ).tap do |a|
          allow(a).to receive(:respond_to?).and_return(false)
          allow(a).to receive(:respond_to?).with(:ai_agent_skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:agent_skills).and_return(skill_relation)
          allow(skill_relation).to receive(:pluck).with(:name).and_return([])
        end
      end

      it 'skips the agent' do
        agents_relation = double('agents_relation')
        allow(agents_relation).to receive(:find_each).and_yield(agent)

        matches = service.match_tools_to_agents(tools, agents_relation)
        expect(matches).to be_empty
      end
    end
  end
end
