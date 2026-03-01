# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ContainerAgentDeploymentService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:agent) do
    create(:ai_agent, account: account, mcp_metadata: {
      "system_prompt" => "You are a helpful assistant",
      "model_config" => { "model" => "claude-sonnet-4-5-20250929", "provider" => "anthropic" }
    })
  end
  let(:user) { create(:user, account: account) }
  let(:conversation_id) { SecureRandom.uuid }
  let(:template) do
    create(:devops_container_template,
           account: account, name: "Autonomous Chat Agent", status: "active",
           timeout_seconds: 3600)
  end
  let(:cluster) do
    Devops::SwarmCluster.create!(
      account: account,
      name: "Test Cluster",
      slug: "test-cluster",
      api_endpoint: "https://swarm.test.local",
      environment: "development",
      status: "connected",
      sync_interval_seconds: 60
    )
  end


  describe "#deploy_agent_session" do
    before { template; cluster }

    it "creates a container instance and starts provisioning" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id, user: user)

      expect(instance).to be_a(Devops::ContainerInstance)
      expect(instance.status).to eq("provisioning")
      expect(instance.account).to eq(account)
      expect(instance.template).to eq(template)
      expect(instance.triggered_by).to eq(user)
      expect(instance.image_name).to eq(template.image_name)
    end

    it "stores agent and conversation metadata in input_parameters" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      params = instance.input_parameters
      expect(params["agent_id"]).to eq(agent.id)
      expect(params["agent_name"]).to eq(agent.name)
      expect(params["conversation_id"]).to eq(conversation_id)
      expect(params["chat_enabled"]).to be true
      expect(params["cluster_name"]).to eq("Test Cluster")
      expect(params["template_name"]).to eq("Autonomous Chat Agent")
    end

    it "stores mcp_metadata fields in input_parameters" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      params = instance.input_parameters
      expect(params["system_prompt"]).to eq("You are a helpful assistant")
      expect(params["model"]).to eq("claude-sonnet-4-5-20250929")
      expect(params["provider"]).to eq("anthropic")
    end

    it "stores swarm service spec and deployment timestamp" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      params = instance.input_parameters
      expect(params["swarm_cluster_id"]).to eq(cluster.id)
      expect(params["service_spec"]).to be_a(Hash)
      expect(params["service_spec"]["Name"]).to start_with("powernode-agent-")
      expect(params["deployment_requested_at"]).to be_present
    end

    it "builds environment variables with required keys" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      env = instance.environment_variables
      expect(env["AGENT_ID"]).to eq(agent.id.to_s)
      expect(env["AGENT_NAME"]).to eq(agent.name)
      expect(env["CONVERSATION_ID"]).to eq(conversation_id.to_s)
      expect(env["PLATFORM_CALLBACK_URL"]).to include("/api/v1/ai/agent_containers/callback")
      expect(env["HEARTBEAT_INTERVAL_SECONDS"]).to eq("30")
      expect(env["PYTHONUNBUFFERED"]).to eq("1")
    end

    it "includes optional env vars from mcp_metadata" do
      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      env = instance.environment_variables
      expect(env["SYSTEM_PROMPT"]).to eq("You are a helpful assistant")
      expect(env["MODEL"]).to eq("claude-sonnet-4-5-20250929")
      expect(env["PROVIDER"]).to eq("anthropic")
    end

    it "uses the provided swarm_cluster instead of auto-detecting" do
      other_cluster = Devops::SwarmCluster.create!(
        account: account,
        name: "Other Cluster",
        slug: "other-cluster",
        api_endpoint: "https://other.test.local",
        environment: "staging",
        status: "connected",
        sync_interval_seconds: 60
      )

      instance = service.deploy_agent_session(
        agent: agent, conversation_id: conversation_id, swarm_cluster: other_cluster
      )

      expect(instance.input_parameters["cluster_name"]).to eq("Other Cluster")
      expect(instance.input_parameters["swarm_cluster_id"]).to eq(other_cluster.id)
    end

    it "falls back to AI Coding Agent template when Autonomous Chat Agent is missing" do
      template.update!(name: "Something Else")
      fallback = create(:devops_container_template, account: account, name: "AI Coding Agent", status: "active")

      instance = service.deploy_agent_session(agent: agent, conversation_id: conversation_id)

      expect(instance.template).to eq(fallback)
    end

    context "when no connected cluster is available" do
      before { cluster.update!(status: "disconnected") }

      it "raises SwarmUnavailableError" do
        expect {
          service.deploy_agent_session(agent: agent, conversation_id: conversation_id)
        }.to raise_error(described_class::SwarmUnavailableError, /No connected Swarm cluster/)
      end
    end

    context "when no template is found" do
      before { template.update!(status: "archived") }

      it "raises TemplateNotFoundError" do
        expect {
          service.deploy_agent_session(agent: agent, conversation_id: conversation_id)
        }.to raise_error(described_class::TemplateNotFoundError, /No chat agent container template/)
      end
    end

    context "when instance creation fails" do
      before do
        allow(Devops::ContainerInstance).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it "raises DeploymentError" do
        expect {
          service.deploy_agent_session(agent: agent, conversation_id: conversation_id)
        }.to raise_error(described_class::DeploymentError, /Failed to deploy agent container/)
      end
    end

    it "marks instance as failed when provisioning raises" do
      instance = create(:devops_container_instance, account: account, template: template, status: "pending")
      allow(Devops::ContainerInstance).to receive(:create!).and_return(instance)
      allow(instance).to receive(:update!).and_call_original
      allow(instance).to receive(:start_provisioning!).and_raise(StandardError, "provisioning boom")

      expect {
        service.deploy_agent_session(agent: agent, conversation_id: conversation_id)
      }.to raise_error(described_class::DeploymentError)

      instance.reload
      expect(instance.status).to eq("failed")
    end
  end

  describe "#terminate_agent_session" do
    let(:instance) { create(:devops_container_instance, :running, account: account, template: template) }

    it "cancels an active container and returns true" do
      result = service.terminate_agent_session(container_instance: instance)

      expect(result).to be true
      instance.reload
      expect(instance.status).to eq("cancelled")
    end

    it "passes the reason to cancel!" do
      service.terminate_agent_session(container_instance: instance, reason: "User requested")

      instance.reload
      expect(instance.status).to eq("cancelled")
    end

    it "returns false for non-active containers" do
      completed = create(:devops_container_instance, :completed, account: account, template: template)

      result = service.terminate_agent_session(container_instance: completed)

      expect(result).to be false
    end

    it "returns false when cancel! raises an error" do
      allow(instance).to receive(:cancel!).and_raise(StandardError, "cancel failed")

      result = service.terminate_agent_session(container_instance: instance)

      expect(result).to be false
    end
  end

  describe "#get_session_status" do
    it "returns status hash for a running container" do
      instance = create(:devops_container_instance, :running, account: account, template: template,
                        input_parameters: { "agent_id" => "agent-1", "conversation_id" => "conv-1",
                                            "swarm_cluster_id" => "cluster-1" },
                        memory_used_mb: 256, cpu_used_millicores: 500)

      status = service.get_session_status(container_instance: instance)

      expect(status[:instance_id]).to eq(instance.id)
      expect(status[:execution_id]).to eq(instance.execution_id)
      expect(status[:status]).to eq("running")
      expect(status[:agent_id]).to eq("agent-1")
      expect(status[:conversation_id]).to eq("conv-1")
      expect(status[:cluster_id]).to eq("cluster-1")
      expect(status[:started_at]).to be_present
      expect(status[:uptime_seconds]).to be_a(Integer)
      expect(status[:uptime_seconds]).to be >= 0
      expect(status[:resource_usage]).to eq({ memory_mb: 256, cpu_millicores: 500 })
    end

    it "returns nil uptime_seconds for non-running containers" do
      instance = create(:devops_container_instance, :completed, account: account, template: template,
                        input_parameters: { "agent_id" => "agent-1" })

      status = service.get_session_status(container_instance: instance)

      expect(status[:uptime_seconds]).to be_nil
    end

    it "returns nil uptime_seconds for pending containers" do
      instance = create(:devops_container_instance, :pending, account: account, template: template,
                        input_parameters: {})

      status = service.get_session_status(container_instance: instance)

      expect(status[:uptime_seconds]).to be_nil
      expect(status[:started_at]).to be_nil
    end
  end

  describe "#active_sessions_for_conversation" do
    before { template }

    it "returns active instances matching the conversation_id" do
      active = create(:devops_container_instance, :running, account: account, template: template,
                      input_parameters: { "conversation_id" => conversation_id })
      create(:devops_container_instance, :completed, account: account, template: template,
             input_parameters: { "conversation_id" => conversation_id })
      create(:devops_container_instance, :running, account: account, template: template,
             input_parameters: { "conversation_id" => "other-conv" })

      results = service.active_sessions_for_conversation(conversation_id)

      expect(results).to contain_exactly(active)
    end

    it "returns empty relation when no active sessions exist" do
      results = service.active_sessions_for_conversation("nonexistent")

      expect(results).to be_empty
    end
  end

  describe "error class hierarchy" do
    it "DeploymentError inherits from StandardError" do
      expect(described_class::DeploymentError.superclass).to eq(StandardError)
    end

    it "SwarmUnavailableError inherits from DeploymentError" do
      expect(described_class::SwarmUnavailableError.superclass).to eq(described_class::DeploymentError)
    end

    it "TemplateNotFoundError inherits from DeploymentError" do
      expect(described_class::TemplateNotFoundError.superclass).to eq(described_class::DeploymentError)
    end
  end
end
