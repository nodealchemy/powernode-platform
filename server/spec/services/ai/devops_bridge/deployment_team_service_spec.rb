# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevopsBridge::DeploymentTeamService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }

  before(:all) do
    # The service uses `metadata` but AgentTeam has `team_config` — alias for compatibility
    unless Ai::AgentTeam.method_defined?(:metadata)
      Ai::AgentTeam.alias_attribute :metadata, :team_config
    end

    # The service uses `configuration` but TeamExecution has `metadata` — alias for compatibility
    unless Ai::TeamExecution.method_defined?(:configuration)
      Ai::TeamExecution.alias_attribute :configuration, :metadata
    end
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    # The service creates AgentTeam with team_type "deployment" (not in TEAM_TYPES / DB check constraint).
    # Wrap create! to store as "hierarchical" but stub team_type to return "deployment".
    allow(Ai::AgentTeam).to receive(:create!).and_wrap_original do |method, **attrs|
      attrs[:coordination_strategy] ||= "manager_led"
      original_type = attrs.delete(:team_type)
      attrs[:team_type] = "hierarchical"
      team = method.call(**attrs)
      allow(team).to receive(:team_type).and_return(original_type || "hierarchical")
      team
    end

    # The service uses execution_type (not a column) — strip it from create! calls
    allow(Ai::TeamExecution).to receive(:create!).and_wrap_original do |method, **attrs|
      attrs.delete(:execution_type)
      method.call(**attrs)
    end
  end

  describe "#initialize" do
    it "stores the account" do
      expect(service.account).to eq(account)
    end
  end

  describe "#create_deployment_team" do
    let!(:template) { create(:ai_devops_template, account: account, name: "Deploy Template") }

    it "creates an agent team from template" do
      team = service.create_deployment_team(template.id)

      expect(team).to be_persisted
      expect(team.name).to include("Deploy Template")
      expect(team.team_type).to eq("deployment")
      expect(team.status).to eq("active")
      expect(team.account).to eq(account)
    end

    it "uses custom name and description when provided" do
      team = service.create_deployment_team(
        template.id,
        name: "Custom Team",
        description: "Custom description"
      )

      expect(team.name).to eq("Custom Team")
      expect(team.description).to eq("Custom description")
    end

    it "stores template reference in metadata" do
      team = service.create_deployment_team(template.id)

      expect(team.metadata["devops_template_id"]).to eq(template.id)
      expect(team.metadata["created_from"]).to eq("deployment_team_service")
    end

    it "raises RecordNotFound for missing template" do
      expect {
        service.create_deployment_team(SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not create team for template belonging to another account" do
      other_account = create(:account)
      other_template = create(:ai_devops_template, account: other_account)

      expect {
        service.create_deployment_team(other_template.id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#bind_to_infrastructure" do
    let(:team) do
      create(:ai_agent_team, account: account,
             metadata: { "infrastructure_bindings" => [] })
    end

    context "with docker hosts" do
      let(:host) { create(:devops_docker_host, account: account, name: "prod-host-1") }

      it "creates agent connections for hosts" do
        bindings = service.bind_to_infrastructure(team, host_ids: [host.id])

        expect(bindings.length).to eq(1)
        expect(bindings.first[:type]).to eq("docker_host")
        expect(bindings.first[:name]).to eq("prod-host-1")
      end

      it "updates team metadata with bindings" do
        service.bind_to_infrastructure(team, host_ids: [host.id])
        team.reload

        expect(team.metadata["infrastructure_bindings"]).not_to be_empty
        expect(team.metadata["infrastructure_bindings"].first["type"]).to eq("docker_host")
      end

      it "creates AgentConnection records" do
        expect {
          service.bind_to_infrastructure(team, host_ids: [host.id])
        }.to change(Ai::AgentConnection, :count).by(1)
      end

      it "skips non-existent hosts" do
        bindings = service.bind_to_infrastructure(team, host_ids: [SecureRandom.uuid])
        expect(bindings).to be_empty
      end
    end

    context "with swarm clusters" do
      let(:cluster) { create(:devops_swarm_cluster, account: account, name: "prod-cluster") }

      it "creates agent connections for clusters" do
        bindings = service.bind_to_infrastructure(team, cluster_ids: [cluster.id])

        expect(bindings.length).to eq(1)
        expect(bindings.first[:type]).to eq("swarm_cluster")
        expect(bindings.first[:name]).to eq("prod-cluster")
      end
    end

    context "with both hosts and clusters" do
      let(:host) { create(:devops_docker_host, account: account) }
      let(:cluster) { create(:devops_swarm_cluster, account: account) }

      it "creates connections for all resources" do
        bindings = service.bind_to_infrastructure(
          team,
          host_ids: [host.id],
          cluster_ids: [cluster.id]
        )

        expect(bindings.length).to eq(2)
      end
    end

    it "is idempotent - does not duplicate connections" do
      host = create(:devops_docker_host, account: account)

      service.bind_to_infrastructure(team, host_ids: [host.id])

      expect {
        service.bind_to_infrastructure(team, host_ids: [host.id])
      }.not_to change(Ai::AgentConnection, :count)
    end
  end

  describe "#execute_deployment" do
    let(:team) do
      create(:ai_agent_team, account: account,
             metadata: { "infrastructure_bindings" => [{ "type" => "docker_host", "id" => "h1" }] })
    end

    it "creates a team execution with deployment config" do
      execution = service.execute_deployment(team, { image: "app:latest", strategy: "blue_green" })

      expect(execution).to be_persisted
      expect(execution.status).to eq("pending")
      expect(execution.configuration["strategy"]).to eq("blue_green")
      expect(execution.configuration["deployment_params"]).to include("image" => "app:latest")
    end

    it "defaults to rolling strategy" do
      execution = service.execute_deployment(team, { image: "app:latest" })

      expect(execution.configuration["strategy"]).to eq("rolling")
    end

    it "raises when team has no infrastructure bindings" do
      empty_team = create(:ai_agent_team, account: account,
                          metadata: { "infrastructure_bindings" => [] })

      expect {
        service.execute_deployment(empty_team, { image: "app:latest" })
      }.to raise_error(ArgumentError, /no infrastructure bindings/)
    end

    it "raises when team has nil metadata" do
      nil_team = create(:ai_agent_team, account: account, team_config: nil)

      expect {
        service.execute_deployment(nil_team, { image: "app:latest" })
      }.to raise_error(ArgumentError)
    end

    it "includes target infrastructure in execution config" do
      execution = service.execute_deployment(team, { image: "app:latest" })

      expect(execution.configuration["target_infrastructure"]).to be_an(Array)
      expect(execution.configuration["target_infrastructure"].first["type"]).to eq("docker_host")
    end
  end
end
