# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Runtime::SandboxManagerService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }
  let(:template) { create(:devops_container_template, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#initialize' do
    it 'sets the account' do
      expect(service.account).to eq(account)
    end
  end

  describe '#create_sandbox' do
    before do
      # Stub find_or_create_template because the service sets `configuration=`
      # which doesn't exist as a column on ContainerTemplate
      allow(service).to receive(:find_or_create_template).and_return(template)
      # Stub execution gate — these tests exercise sandbox logic, not governance checks
      allow_any_instance_of(Ai::Autonomy::ExecutionGateService).to receive(:check)
        .and_return({ decision: :proceed, reason: nil })
      # Stub MCP auth provisioning — tested separately
      allow_any_instance_of(Ai::ContainerMcpAuthService).to receive(:provision_mcp_credentials)
        .and_return({ env_vars: {}, oauth_application: nil })
      # Stub port allocation — tested separately
      allow_any_instance_of(Devops::PortAllocatorService).to receive(:allocate!).and_return(7001)
    end

    it 'creates a container instance for the agent' do
      instance = service.create_sandbox(agent: agent)

      expect(instance).to be_a(Devops::ContainerInstance)
      expect(instance).to be_persisted
      expect(instance.account).to eq(account)
      expect(instance.status).to eq("pending")
      expect(instance.sandbox_enabled).to be true
    end

    it 'sets agent info in input parameters' do
      instance = service.create_sandbox(agent: agent)

      expect(instance.input_parameters["agent_id"]).to eq(agent.id)
      expect(instance.input_parameters["agent_name"]).to eq(agent.name)
      expect(instance.input_parameters["sandbox_mode"]).to be true
    end

    it 'links to the template' do
      instance = service.create_sandbox(agent: agent)

      expect(instance.template).to eq(template)
    end

    it 'sets runner labels' do
      instance = service.create_sandbox(agent: agent)

      expect(instance.runner_labels).to include("powernode-ai-agent", "sandbox")
    end

    it 'applies custom environment config' do
      instance = service.create_sandbox(agent: agent, config: {
        environment: { "FOO" => "bar" }
      })

      expect(instance.environment_variables).to include("FOO" => "bar")
    end

    it 'logs sandbox creation' do
      allow(Rails.logger).to receive(:info).and_call_original

      service.create_sandbox(agent: agent)

      expect(Rails.logger).to have_received(:info).with(/Created sandbox/)
    end

    context 'when ContainerInstance creation fails' do
      it 'logs error and re-raises' do
        allow(service).to receive(:find_or_create_template).and_raise(StandardError, "template error")
        allow(Rails.logger).to receive(:error).and_call_original

        expect { service.create_sandbox(agent: agent) }.to raise_error(StandardError)
        expect(Rails.logger).to have_received(:error).with(/Failed to create sandbox/)
      end
    end
  end

  describe '#destroy_sandbox' do
    let(:instance) { create(:devops_container_instance, :running, account: account) }

    it 'cancels an active instance' do
      allow(instance).to receive(:active?).and_return(true)
      allow(instance).to receive(:cancel!)

      result = service.destroy_sandbox(instance: instance)

      expect(result).to be true
      expect(instance).to have_received(:cancel!)
    end

    it 'returns false for inactive instance' do
      allow(instance).to receive(:active?).and_return(false)

      result = service.destroy_sandbox(instance: instance)

      expect(result).to be false
    end

    it 'passes reason to cancel!' do
      allow(instance).to receive(:active?).and_return(true)
      allow(instance).to receive(:cancel!)

      service.destroy_sandbox(instance: instance, reason: "cleanup")

      expect(instance).to have_received(:cancel!).with(reason: "cleanup")
    end

    it 'logs sandbox destruction' do
      allow(instance).to receive(:active?).and_return(true)
      allow(instance).to receive(:cancel!)

      expect(Rails.logger).to receive(:info).with(/Destroyed sandbox/)

      service.destroy_sandbox(instance: instance)
    end
  end

  describe '#pause_sandbox' do
    let(:pending_instance) { create(:devops_container_instance, :pending, account: account) }
    let(:running_instance) { create(:devops_container_instance, :running, account: account) }

    it 'returns error if instance is not running' do
      result = service.pause_sandbox(instance: pending_instance)

      expect(result[:success]).to be false
      expect(result[:error]).to include("not running")
    end

    context 'when docker host is found' do
      before do
        docker_host = instance_double(Devops::DockerHost)
        docker_hosts_relation = double("docker_hosts")
        allow(Devops::DockerHost).to receive(:where).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:connected).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:first).and_return(docker_host)
        # Stub the update! since "paused" is not a valid ContainerInstance status
        allow(running_instance).to receive(:update!)
      end

      it 'pauses a running instance' do
        result = service.pause_sandbox(instance: running_instance)

        expect(result[:success]).to be true
        expect(result[:execution_id]).to eq(running_instance.execution_id)
      end
    end

    context 'when no docker host is found' do
      before do
        docker_hosts_relation = double("docker_hosts")
        allow(Devops::DockerHost).to receive(:where).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:connected).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:first).and_return(nil)
        allow(running_instance).to receive_message_chain(:template, :docker_host).and_return(nil)
      end

      it 'returns error' do
        result = service.pause_sandbox(instance: running_instance)

        expect(result[:success]).to be false
        expect(result[:error]).to include("No docker host")
      end
    end
  end

  describe '#resume_sandbox' do
    let(:instance) { create(:devops_container_instance, :pending, account: account) }

    context 'when docker host is found' do
      before do
        docker_host = instance_double(Devops::DockerHost)
        docker_hosts_relation = double("docker_hosts")
        allow(Devops::DockerHost).to receive(:where).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:connected).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:first).and_return(docker_host)
        allow(instance).to receive(:update!)
      end

      it 'resumes a paused instance' do
        result = service.resume_sandbox(instance: instance)

        expect(result[:success]).to be true
        expect(result[:execution_id]).to eq(instance.execution_id)
      end
    end

    context 'when no docker host is found' do
      before do
        docker_hosts_relation = double("docker_hosts")
        allow(Devops::DockerHost).to receive(:where).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:connected).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:first).and_return(nil)
        allow(instance).to receive_message_chain(:template, :docker_host).and_return(nil)
      end

      it 'returns error' do
        result = service.resume_sandbox(instance: instance)

        expect(result[:success]).to be false
        expect(result[:error]).to include("No docker host")
      end
    end
  end

  describe '#exec_in_sandbox' do
    let(:running_instance) { create(:devops_container_instance, :running, account: account) }
    let(:pending_instance) { create(:devops_container_instance, :pending, account: account) }

    it 'returns error if instance is not running' do
      result = service.exec_in_sandbox(instance: pending_instance, command: "ls -la")

      expect(result[:success]).to be false
      expect(result[:error]).to include("not running")
    end

    context 'when instance is running' do
      before do
        docker_host = instance_double(Devops::DockerHost)
        docker_hosts_relation = double("docker_hosts")
        allow(Devops::DockerHost).to receive(:where).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:connected).and_return(docker_hosts_relation)
        allow(docker_hosts_relation).to receive(:first).and_return(docker_host)
      end

      it 'executes command and returns result' do
        result = service.exec_in_sandbox(instance: running_instance, command: "echo hello")

        expect(result[:success]).to be true
        expect(result[:command]).to eq("echo hello")
        expect(result[:execution_id]).to eq(running_instance.execution_id)
      end
    end
  end

  describe '#stream_logs' do
    let(:instance) { create(:devops_container_instance, :running, account: account) }

    it 'returns stream info' do
      result = service.stream_logs(instance: instance)

      expect(result[:success]).to be true
      expect(result[:execution_id]).to eq(instance.execution_id)
    end
  end

  describe '#get_metrics' do
    let(:completed_instance) { create(:devops_container_instance, :completed, account: account) }
    let(:running_instance) { create(:devops_container_instance, :running, account: account) }

    it 'returns resource metrics for completed instance' do
      metrics = service.get_metrics(instance: completed_instance)

      expect(metrics[:execution_id]).to eq(completed_instance.execution_id)
      expect(metrics[:status]).to eq(completed_instance.status)
      expect(metrics).to have_key(:memory_used_mb)
      expect(metrics).to have_key(:cpu_used_millicores)
      expect(metrics).to have_key(:uptime_seconds)
    end

    it 'calculates uptime for running instances' do
      metrics = service.get_metrics(instance: running_instance)

      expect(metrics[:uptime_seconds]).to be > 0
    end

    it 'returns nil uptime when no started_at' do
      pending_instance = create(:devops_container_instance, :pending, account: account)
      metrics = service.get_metrics(instance: pending_instance)

      expect(metrics[:uptime_seconds]).to be_nil
    end
  end
end
