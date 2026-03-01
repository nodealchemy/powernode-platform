# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Discovery::InfrastructureScannerService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#scan_docker_hosts' do
    before do
      allow(Devops::DockerHost).to receive(:where).with(account: account).and_return(hosts_relation)
      allow(Ai::Agent).to receive(:where).with(account: account).and_return(agents_relation)
    end

    let(:hosts_relation) { double('hosts_relation') }
    let(:agents_relation) { double('agents_relation') }

    context 'with no hosts' do
      before do
        allow(hosts_relation).to receive(:find_each)
      end

      it 'returns empty results' do
        result = service.scan_docker_hosts

        expect(result[:agents]).to be_empty
        expect(result[:connections]).to be_empty
      end
    end

    context 'with a host containing matching containers' do
      let(:agent) { create(:ai_agent, account: account, name: "my-agent") }
      let(:container) do
        double('container',
          id: "container-1",
          name: "my-agent-worker",
          status: "running",
          labels: { "ai.agent.id" => agent.id }
        )
      end
      let(:host) do
        double('host',
          id: SecureRandom.uuid,
          name: "docker-host-1",
          docker_containers: [container]
        )
      end

      before do
        allow(hosts_relation).to receive(:find_each).and_yield(host)
        allow(agents_relation).to receive(:pluck).with(:id, :name).and_return([[agent.id, agent.name]])
        allow(agents_relation).to receive(:each) do |&block|
          [agent].each(&block)
        end
      end

      it 'discovers agents from containers by label' do
        result = service.scan_docker_hosts

        expect(result[:agents].size).to eq(1)
        expect(result[:agents].first[:id]).to eq(agent.id)
        expect(result[:agents].first[:metadata][:infrastructure]).to eq("docker")
      end

      it 'creates infrastructure connections' do
        result = service.scan_docker_hosts

        expect(result[:connections].size).to eq(1)
        conn = result[:connections].first
        expect(conn[:source_type]).to eq("Ai::Agent")
        expect(conn[:target_type]).to eq("Devops::DockerHost")
        expect(conn[:connection_type]).to eq("infrastructure")
      end
    end

    context 'with name-based container matching' do
      let(:agent) { create(:ai_agent, account: account, name: "Code Reviewer") }
      let(:container) do
        double('container',
          id: "container-2",
          name: "code-reviewer-service",
          status: "running",
          labels: {}
        )
      end
      let(:host) do
        double('host',
          id: SecureRandom.uuid,
          name: "docker-host-1",
          docker_containers: [container]
        )
      end

      before do
        allow(hosts_relation).to receive(:find_each).and_yield(host)
        allow(agents_relation).to receive(:pluck).with(:id, :name).and_return([[agent.id, agent.name]])
        # Need to make agents iterable for name matching
        allow(agents_relation).to receive(:each) do |&block|
          [agent].each(&block)
        end
      end

      it 'matches containers by name similarity' do
        result = service.scan_docker_hosts

        expect(result[:agents].size).to eq(1)
        expect(result[:agents].first[:name]).to eq("Code Reviewer")
      end
    end
  end

  describe '#scan_swarm_clusters' do
    before do
      allow(Devops::SwarmCluster).to receive(:where).with(account: account).and_return(clusters_relation)
      allow(Ai::Agent).to receive(:where).with(account: account).and_return(agents_relation)
    end

    let(:clusters_relation) { double('clusters_relation') }
    let(:agents_relation) { double('agents_relation') }

    context 'with no clusters' do
      before do
        allow(clusters_relation).to receive(:find_each)
      end

      it 'returns empty results' do
        result = service.scan_swarm_clusters

        expect(result[:agents]).to be_empty
        expect(result[:connections]).to be_empty
      end
    end

    context 'with cluster containing matching services' do
      let(:agent) { create(:ai_agent, account: account, name: "analyzer") }
      let(:swarm_service) do
        double('swarm_service',
          id: "service-1",
          name: "analyzer-service",
          status: "running",
          labels: { "powernode.agent_id" => agent.id },
          replicas: 3
        )
      end
      let(:cluster) do
        double('cluster',
          id: SecureRandom.uuid,
          name: "swarm-cluster-1",
          swarm_services: [swarm_service]
        )
      end

      before do
        allow(clusters_relation).to receive(:find_each).and_yield(cluster)
        allow(agents_relation).to receive(:find_by).with(id: agent.id).and_return(agent)
        allow(agents_relation).to receive(:each) do |&block|
          [agent].each(&block)
        end
      end

      it 'discovers agents from swarm services' do
        result = service.scan_swarm_clusters

        expect(result[:agents].size).to eq(1)
        expect(result[:agents].first[:metadata][:infrastructure]).to eq("swarm")
        expect(result[:agents].first[:metadata][:replicas]).to eq(3)
      end

      it 'creates cluster connections' do
        result = service.scan_swarm_clusters

        expect(result[:connections].size).to eq(1)
        expect(result[:connections].first[:target_type]).to eq("Devops::SwarmCluster")
      end
    end
  end

  describe '#build_infrastructure_connections' do
    let(:agent) { create(:ai_agent, account: account, name: "test-agent") }
    let(:container) do
      double('container', id: "c1", name: "test-agent-worker", labels: { "ai.agent.id" => agent.id })
    end
    let(:host) do
      double('host', id: SecureRandom.uuid, docker_containers: [container])
    end
    let(:agents_proxy) do
      proxy = double('agents_proxy')
      allow(proxy).to receive(:find_by).with(id: agent.id).and_return(agent)
      allow(proxy).to receive(:find_by) { |args| args[:id] == agent.id ? agent : nil }
      allow(proxy).to receive(:each) { |&block| [agent].each(&block) }
      allow(proxy).to receive(:detect) { |&block| [agent].detect(&block) }
      proxy
    end

    it 'builds connections for matching containers' do
      connections = service.build_infrastructure_connections([host], [], agents_proxy)

      expect(connections.size).to eq(1)
      expect(connections.first[:source_id]).to eq(agent.id)
      expect(connections.first[:target_type]).to eq("Devops::DockerHost")
    end

    it 'returns empty for no matches' do
      no_match_container = double('container', id: "c2", name: "unrelated", labels: {})
      host2 = double('host', id: SecureRandom.uuid, docker_containers: [no_match_container])

      empty_agents = double('empty_agents')
      allow(empty_agents).to receive(:find_by).and_return(nil)
      allow(empty_agents).to receive(:each) { |&block| [].each(&block) }
      allow(empty_agents).to receive(:detect) { |&block| [].detect(&block) }

      connections = service.build_infrastructure_connections([host2], [], empty_agents)
      expect(connections).to be_empty
    end
  end
end
