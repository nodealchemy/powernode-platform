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
      # The service reads skill names via the :skills through-association.
      # Use a plain double to isolate the matching logic from the DB.
      let(:agent) do
        double('agent',
          id: SecureRandom.uuid,
          name: "Code Agent",
          description: "Agent for code tasks",
          status: "active",
          created_at: Time.current
        ).tap do |a|
          allow(a).to receive(:respond_to?).and_return(false)
          allow(a).to receive(:respond_to?).with(:skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)
          allow(a).to receive(:respond_to?).with(:status).and_return(true)
          allow(a).to receive(:respond_to?).with(:provider).and_return(false)
          allow(a).to receive(:respond_to?).with(:model).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:skills).and_return(skill_relation)
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
          allow(a).to receive(:respond_to?).with(:skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:skills).and_return(skill_relation)
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
          allow(a).to receive(:respond_to?).with(:skills).and_return(true)
          allow(a).to receive(:respond_to?).with(:capabilities).and_return(false)

          skill_relation = double('skill_relation')
          allow(a).to receive(:skills).and_return(skill_relation)
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

    # Regression (real model, not a double): extract_agent_skills guarded on
    # respond_to?(:ai_agent_skills), but Ai::Agent's association is :skills
    # (through :agent_skills) — so on a REAL agent the guard was always false and
    # skill extraction returned [], making MCP tool->agent discovery find zero
    # matches regardless of the agent's actual skills. The double-based examples
    # above cannot catch this because they mock the association.
    context 'with a REAL agent whose skills match a tool keyword' do
      let!(:skilled_agent) { create(:ai_agent, account: account) }
      let!(:skill) { create(:ai_skill, account: account, name: "code", slug: "code-skill") }

      before { create(:ai_agent_skill, agent: skilled_agent, skill: skill) }

      it 'reads the real skill names and matches tools' do
        matches = service.match_tools_to_agents(tools, Ai::Agent.where(account: account))

        rec = matches.find { |m| m[:agent_id] == skilled_agent.id }
        expect(rec).to be_present
        expect(rec[:matched_tools]).to include("code_search")
      end
    end
  end
end
