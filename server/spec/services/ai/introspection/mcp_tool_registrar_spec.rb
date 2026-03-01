# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Introspection::McpToolRegistrar do
  let(:account) { create(:account) }

  describe 'INTROSPECTION_TOOLS' do
    it 'defines all expected tool IDs' do
      tool_ids = described_class::INTROSPECTION_TOOLS.map { |t| t[:id] }

      expect(tool_ids).to include(
        "platform.health",
        "platform.metrics",
        "platform.provider_health",
        "platform.alerts",
        "platform.infrastructure",
        "platform.cost_analysis",
        "platform.recent_events",
        "platform.resources",
        "platform.config"
      )
    end

    it 'has valid structure for each tool' do
      described_class::INTROSPECTION_TOOLS.each do |tool|
        expect(tool).to have_key(:id)
        expect(tool).to have_key(:name)
        expect(tool).to have_key(:description)
        expect(tool).to have_key(:category)
        expect(tool).to have_key(:permission_level)
        expect(tool).to have_key(:required_permissions)
        expect(tool).to have_key(:input_schema)
        expect(tool[:category]).to eq("introspection")
      end
    end

    it 'is frozen' do
      expect(described_class::INTROSPECTION_TOOLS).to be_frozen
    end
  end

  describe '.register_all!' do
    let(:registry) { instance_double(Mcp::RegistryService) }

    before do
      # Inside Ai::Introspection, `Mcp::RegistryService` resolves to Ai::Mcp::RegistryService
      # because Ai::Mcp namespace exists. Stub the constant so the class lookup succeeds.
      stub_const("Ai::Mcp::RegistryService", Mcp::RegistryService)
      allow(Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)
    end

    it 'registers all introspection tools with the registry' do
      allow(registry).to receive(:register_tool)

      described_class.register_all!(account: account)

      expect(registry).to have_received(:register_tool).exactly(described_class::INTROSPECTION_TOOLS.size).times
    end

    it 'registers each tool with the correct id' do
      allow(registry).to receive(:register_tool)

      described_class.register_all!(account: account)

      described_class::INTROSPECTION_TOOLS.each do |tool_def|
        expect(registry).to have_received(:register_tool).with(
          tool_def[:id],
          hash_including(
            name: tool_def[:name],
            description: tool_def[:description],
            category: "introspection",
            version: "1.0.0",
            rate_limited: true
          )
        )
      end
    end

    it 'logs a warning and continues when a tool registration fails' do
      allow(registry).to receive(:register_tool).and_raise(StandardError, "registration error")

      expect(Rails.logger).to receive(:warn).at_least(:once)

      expect { described_class.register_all!(account: account) }.not_to raise_error
    end
  end

  describe '.execute_tool' do
    # Use plain doubles because the service code calls methods that may be
    # defined dynamically or not yet implemented (e.g., provider_metrics, cost_analysis)
    let(:metrics_service) { double("DashboardService") }
    let(:health_service) { double("MonitoringHealthService") }
    let(:introspection_service) { double("PlatformIntrospectionService") }

    before do
      allow(Ai::Analytics::DashboardService).to receive(:new).with(account: account).and_return(metrics_service)
      allow(Ai::MonitoringHealthService).to receive(:new).with(account: account).and_return(health_service)
      allow(Ai::Introspection::PlatformIntrospectionService).to receive(:new).with(account: account).and_return(introspection_service)
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:agent_introspection).and_return(true)
    end

    context 'when feature flag is disabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:agent_introspection).and_return(false)
      end

      it 'returns nil' do
        result = described_class.execute_tool("platform.health", params: {}, account: account)
        expect(result).to be_nil
      end
    end

    context 'with agent_id rate limiting' do
      it 'calls RateLimiter.check! when agent_id is provided' do
        allow(Ai::Introspection::RateLimiter).to receive(:check!)
        allow(metrics_service).to receive(:system_health).and_return({ status: "ok" })

        described_class.execute_tool("platform.health", params: {}, account: account, agent_id: "agent-123")

        expect(Ai::Introspection::RateLimiter).to have_received(:check!).with(agent_id: "agent-123")
      end

      it 'does not call RateLimiter when no agent_id' do
        allow(Ai::Introspection::RateLimiter).to receive(:check!)
        allow(metrics_service).to receive(:system_health).and_return({ status: "ok" })

        described_class.execute_tool("platform.health", params: {}, account: account)

        expect(Ai::Introspection::RateLimiter).not_to have_received(:check!)
      end
    end

    context 'platform.health' do
      it 'delegates to metrics_service.system_health' do
        allow(metrics_service).to receive(:system_health).and_return({ score: 0.95 })

        result = described_class.execute_tool("platform.health", params: {}, account: account)

        expect(result).to eq({ score: 0.95 })
        expect(metrics_service).to have_received(:system_health)
      end
    end

    context 'platform.metrics' do
      it 'delegates to metrics_service.system_overview with default time range' do
        allow(metrics_service).to receive(:system_overview).and_return({ workflows: 5 })

        result = described_class.execute_tool("platform.metrics", params: {}, account: account)

        expect(result).to eq({ workflows: 5 })
        expect(metrics_service).to have_received(:system_overview).with(60.minutes)
      end

      it 'uses custom time_range_minutes parameter' do
        allow(metrics_service).to receive(:system_overview).and_return({ workflows: 5 })

        described_class.execute_tool("platform.metrics", params: { time_range_minutes: 120 }, account: account)

        expect(metrics_service).to have_received(:system_overview).with(120.minutes)
      end
    end

    context 'platform.provider_health' do
      it 'delegates to metrics_service.provider_metrics' do
        allow(metrics_service).to receive(:provider_metrics).and_return({ providers: [] })

        result = described_class.execute_tool("platform.provider_health", params: {}, account: account)

        expect(result).to eq({ providers: [] })
      end
    end

    context 'platform.alerts' do
      it 'delegates to metrics_service.active_alerts' do
        allow(metrics_service).to receive(:active_alerts).and_return({ alerts: [] })

        result = described_class.execute_tool("platform.alerts", params: {}, account: account)

        expect(result).to eq({ alerts: [] })
      end
    end

    context 'platform.infrastructure' do
      it 'delegates to health_service.comprehensive_health_check' do
        allow(health_service).to receive(:comprehensive_health_check).and_return({ db: "ok" })

        result = described_class.execute_tool("platform.infrastructure", params: {}, account: account)

        expect(result).to eq({ db: "ok" })
        expect(health_service).to have_received(:comprehensive_health_check).with(skip_cache: false)
      end

      it 'passes skip_cache parameter' do
        allow(health_service).to receive(:comprehensive_health_check).and_return({ db: "ok" })

        described_class.execute_tool("platform.infrastructure", params: { skip_cache: true }, account: account)

        expect(health_service).to have_received(:comprehensive_health_check).with(skip_cache: true)
      end
    end

    context 'platform.cost_analysis' do
      it 'delegates to metrics_service.cost_analysis' do
        allow(metrics_service).to receive(:cost_analysis).and_return({ total: 10.0 })

        result = described_class.execute_tool("platform.cost_analysis", params: {}, account: account)

        expect(result).to eq({ total: 10.0 })
      end
    end

    context 'platform.recent_events' do
      it 'delegates to introspection_service.recent_events' do
        allow(introspection_service).to receive(:recent_events).and_return({ events: [] })

        result = described_class.execute_tool("platform.recent_events", params: {}, account: account)

        expect(result).to eq({ events: [] })
        expect(introspection_service).to have_received(:recent_events).with(
          source_type: nil,
          status: nil,
          limit: 50
        )
      end

      it 'passes filter parameters' do
        allow(introspection_service).to receive(:recent_events).and_return({ events: [] })

        described_class.execute_tool("platform.recent_events", params: {
          source_type: "workflow",
          status: "failed",
          limit: 10
        }, account: account)

        expect(introspection_service).to have_received(:recent_events).with(
          source_type: "workflow",
          status: "failed",
          limit: 10
        )
      end
    end

    context 'platform.resources' do
      it 'delegates to introspection_service.list_resources' do
        allow(introspection_service).to receive(:list_resources).and_return({ agents: [] })

        result = described_class.execute_tool("platform.resources", params: { resource_type: "agents" }, account: account)

        expect(result).to eq({ agents: [] })
        expect(introspection_service).to have_received(:list_resources).with(type: "agents")
      end
    end

    context 'platform.config' do
      it 'delegates to introspection_service.get_resource_config' do
        allow(introspection_service).to receive(:get_resource_config).and_return({ name: "test" })

        result = described_class.execute_tool("platform.config", params: {
          resource_type: "agents",
          resource_id: "abc-123"
        }, account: account)

        expect(result).to eq({ name: "test" })
        expect(introspection_service).to have_received(:get_resource_config).with(type: "agents", id: "abc-123")
      end
    end

    context 'with unknown tool_id' do
      it 'returns nil' do
        result = described_class.execute_tool("unknown.tool", params: {}, account: account)
        expect(result).to be_nil
      end
    end
  end
end
