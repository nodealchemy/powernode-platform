# frozen_string_literal: true

require "rails_helper"

# IMP-48abfa2f9e74 — the ten devops MCP tool classes gated on permission names
# that were never in the catalog (docker.containers.read, swarm.services.read,
# kubernetes.clusters.read, ...). User#has_permission? is an exact match on a
# role_permissions row plus a system.admin short-circuit, so no row could ever
# exist for an undeclared name: every one of those ~61 actions was
# super-admin-only while tools/list advertised them to everybody.
#
# The fix RETARGETS each floor onto the declared devops.* family that
# b7598df74 put on the REST twins. That alone would be an escalation: a floor
# of devops.docker.read newly GRANTS docker_container_exec to every read
# holder. So the floor retarget ships with a per-action ACTION_PERMISSIONS
# ladder that raises every write/exec action to devops.*.manage, matching the
# REST twin's own read/manage split action for action.
#
# ORACLES ARE EFFECTS, NOT STRINGS. A refusal asserts the manager that performs
# the operation was never constructed — a message-only assertion cannot tell a
# permission gate from a coincidental domain error (no connected host, Docker
# API unreachable), and both are easy to hit here.
RSpec.describe "devops MCP tools: per-action authorization" do
  let(:account) { create(:account) }

  # The first user in an account gets the OWNER role, so every actor below
  # declares its permissions explicitly.
  let!(:owner) { create(:user, account: account) }

  let(:docker_reader)  { create(:user, account: account, permissions: %w[devops.docker.read]) }
  let(:docker_manager) { create(:user, account: account, permissions: %w[devops.docker.read devops.docker.manage]) }
  let(:swarm_reader)   { create(:user, account: account, permissions: %w[devops.swarm.read]) }
  let(:swarm_manager)  { create(:user, account: account, permissions: %w[devops.swarm.read devops.swarm.manage]) }
  let(:k8s_reader)     { create(:user, account: account, permissions: %w[devops.kubernetes.read]) }

  def run(tool_name, params = {}, user:)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.#{tool_name}", params: params, account: account, user: user, mcp_agent: nil
    )
  rescue ::Mcp::ProtocolService::PermissionDeniedError => e
    # A refusal is a refusal whether it surfaces as an error result (the
    # per-action ladder) or a raise (the registrar's floor).
    { success: false, error: e.message }
  end

  # THE SMUGGLE PATH — the reason the ladder gates on the RUNNING action rather
  # than the invoked tool name, and the case every other example here misses.
  #
  # A user principal is NOT pinned to the tool name it invoked
  # (McpPlatformToolRegistrar#action_pinned_to_name? returns false for a user),
  # so a caller-supplied :action survives and is what the dispatch actually
  # runs. Every other example in this file omits :action and therefore only
  # exercises the pinned path, where the registry injects the name — which
  # would stay green even if enforcement keyed on the invoked name.
  #
  # So: enter through a READ tool, ask for a MANAGE action.
  describe "a read-tier tool invoked with a sibling manage action" do
    it "refuses docker_container_exec smuggled in through docker_list_containers" do
      result = run("docker_list_containers",
                   { action: "docker_container_exec", host_id: SecureRandom.uuid,
                     container_id: "abc123", command: %w[id] },
                   user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    it "still refuses when the smuggled action targets a different class's verb" do
      result = run("docker_list_containers",
                   { action: "docker_delete_container", host_id: SecureRandom.uuid,
                     container_id: "abc123" },
                   user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    # Control: the same smuggle from a MANAGE holder is a permission pass, so
    # the refusals above are the ladder acting and not the params being
    # rejected for some unrelated reason.
    it "does not refuse the same smuggled action for a manage holder" do
      result = run("docker_list_containers",
                   { action: "docker_container_exec", host_id: SecureRandom.uuid,
                     container_id: "abc123", command: %w[id] },
                   user: docker_manager)

      expect(result[:error].to_s).not_to include("devops.docker.manage")
    end
  end

  def expect_refused(result, permission)
    expect(result[:success]).to be_falsey
    expect(result[:error].to_s).to match(/permission|denied|requires/i)
    expect(result[:error].to_s).to include(permission)
  end

  def expect_not_a_permission_error(result)
    expect(result[:error].to_s).not_to match(/permission|denied|requires/i)
  end

  # === The named red-first case ===================================================
  describe "Ai::Tools::DockerContainerTool (floor devops.docker.read)" do
    let!(:host) { create(:devops_docker_host, :connected, account: account) }
    let!(:container) { create(:devops_docker_container, :running, docker_host: host) }

    it "lets a devops.docker.read holder call docker_list_containers" do
      result = run("docker_list_containers", { "host_id" => host.id }, user: docker_reader)

      expect(result[:success]).to be(true)
      expect(result[:containers].map { |c| c[:name] }).to include(container.name)
    end

    it "refuses docker_container_exec from a devops.docker.read holder, and never reaches the daemon" do
      expect(::Devops::Docker::ContainerManager).not_to receive(:new)

      result = run("docker_container_exec",
                   { "host_id" => host.id, "container_id" => container.id, "command" => %w[id] },
                   user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    it "lets a devops.docker.manage holder call docker_container_exec" do
      manager = instance_double(::Devops::Docker::ContainerManager)
      allow(::Devops::Docker::ContainerManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:exec_command).and_return({ output: "uid=0", exit_code: 0 })

      result = run("docker_container_exec",
                   { "host_id" => host.id, "container_id" => container.id, "command" => %w[id] },
                   user: docker_manager)

      expect(result[:success]).to be(true)
      expect(result[:exit_code]).to eq(0)
    end

    it "refuses docker_delete_container from a read holder and the row survives" do
      expect(::Devops::Docker::ContainerManager).not_to receive(:new)

      result = nil
      expect {
        result = run("docker_delete_container",
                     { "host_id" => host.id, "container_id" => container.id }, user: docker_reader)
      }.not_to change { ::Devops::DockerContainer.where(docker_host_id: host.id).count }

      expect_refused(result, "devops.docker.manage")
      expect(::Devops::DockerContainer.find_by(id: container.id)).to be_present
    end

    it "keeps the read-classified actions at the floor (logs, stats)" do
      manager = instance_double(::Devops::Docker::ContainerManager)
      allow(::Devops::Docker::ContainerManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:container_logs).and_return([ "line" ])
      allow(manager).to receive(:container_stats).and_return({ "cpu" => 1 })

      logs = run("docker_container_logs",
                 { "host_id" => host.id, "container_id" => container.id }, user: docker_reader)
      stats = run("docker_container_stats",
                  { "host_id" => host.id, "container_id" => container.id }, user: docker_reader)

      expect(logs[:success]).to be(true)
      expect(stats[:success]).to be(true)
    end
  end

  # === Floor retarget must not leave a hole anywhere else ==========================
  describe "Ai::Tools::DockerHostTool (floor devops.docker.read)" do
    let!(:host) { create(:devops_docker_host, :connected, account: account) }

    it "refuses docker_sync_host from a read holder without touching the host manager" do
      expect(::Devops::Docker::HostManager).not_to receive(:new)

      result = run("docker_sync_host", { "host_id" => host.id }, user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    it "allows docker_test_host at the read floor (a connectivity probe, as its REST twin is gated)" do
      manager = instance_double(::Devops::Docker::HostManager)
      allow(::Devops::Docker::HostManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:test_connection).and_return({ success: true, server_version: "27.0" })

      result = run("docker_test_host", { "host_id" => host.id }, user: docker_reader)

      expect(result[:success]).to be(true)
    end
  end

  describe "Ai::Tools::DockerImageTool (floor devops.docker.read)" do
    let!(:host) { create(:devops_docker_host, :connected, account: account) }

    it "refuses docker_pull_image from a read holder" do
      expect(::Devops::Docker::ImageManager).not_to receive(:new)

      result = run("docker_pull_image", { "host_id" => host.id, "image" => "nginx" }, user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    it "still lists images at the read floor" do
      result = run("docker_list_images", { "host_id" => host.id }, user: docker_reader)

      expect(result[:success]).to be(true)
    end
  end

  describe "Ai::Tools::DockerServiceTool (floor devops.swarm.read)" do
    let!(:cluster) { create(:devops_swarm_cluster, account: account) }

    it "refuses docker_scale_service from a swarm read holder" do
      expect(::Devops::Docker::ServiceManager).not_to receive(:new)

      result = run("docker_scale_service",
                   { "cluster_id" => cluster.id, "service_id" => "svc", "replicas" => 5 },
                   user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end

    it "still lists services at the read floor" do
      result = run("docker_list_services", { "cluster_id" => cluster.id }, user: swarm_reader)

      expect(result[:success]).to be(true)
    end
  end

  describe "Ai::Tools::DockerClusterTool (floor devops.swarm.read)" do
    let!(:cluster) { create(:devops_swarm_cluster, account: account) }

    it "refuses docker_create_secret from a swarm read holder" do
      expect(::Devops::Docker::SecretManager).not_to receive(:new)

      result = run("docker_create_secret",
                   { "cluster_id" => cluster.id, "name" => "s", "data" => "v" }, user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end

    it "refuses docker_node_drain from a swarm read holder" do
      expect(::Devops::Docker::NodeManager).not_to receive(:new)

      result = run("docker_node_drain", { "cluster_id" => cluster.id, "node_id" => "n" }, user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end

    it "still lists clusters at the read floor" do
      result = run("docker_list_clusters", {}, user: swarm_reader)

      expect(result[:success]).to be(true)
    end
  end

  describe "Ai::Tools::DockerStackTool (floor devops.swarm.read)" do
    let!(:cluster) { create(:devops_swarm_cluster, account: account) }

    it "refuses docker_adopt_stack from a swarm read holder (it relabels live services)" do
      expect(::Devops::Docker::SwarmManager).not_to receive(:new)

      result = run("docker_adopt_stack",
                   { "cluster_id" => cluster.id, "stack_name" => "web" }, user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end

    it "refuses docker_deploy_stack from a swarm read holder and writes no stack row" do
      result = nil
      expect {
        result = run("docker_deploy_stack",
                     { "cluster_id" => cluster.id, "stack_name" => "web", "compose_file" => "services: {}" },
                     user: swarm_reader)
      }.not_to change { ::Devops::SwarmStack.where(cluster_id: cluster.id).count }

      expect_refused(result, "devops.swarm.manage")
    end

    it "lets a swarm manage holder past the ladder into docker_adopt_stack" do
      swarm_mgr = instance_double(::Devops::Docker::SwarmManager)
      allow(::Devops::Docker::SwarmManager).to receive(:new).and_return(swarm_mgr)
      allow(swarm_mgr).to receive(:adopt_stack).and_return({ success: true })

      result = run("docker_adopt_stack",
                   { "cluster_id" => cluster.id, "stack_name" => "web" }, user: swarm_manager)

      expect(result[:success]).to be(true)
    end
  end

  describe "Ai::Tools::DockerNetworkVolumeTool (floor devops.swarm.read — it resolves a SWARM cluster)" do
    let!(:cluster) { create(:devops_swarm_cluster, account: account) }

    it "refuses docker_create_network from a swarm read holder" do
      expect(::Devops::Docker::NetworkManager).not_to receive(:new)

      result = run("docker_create_network", { "cluster_id" => cluster.id, "name" => "net" }, user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end

    it "refuses docker_delete_volume from a swarm read holder" do
      expect(::Devops::Docker::VolumeManager).not_to receive(:new)

      result = run("docker_delete_volume", { "cluster_id" => cluster.id, "volume_name" => "v" }, user: swarm_reader)

      expect_refused(result, "devops.swarm.manage")
    end
  end

  describe "Ai::Tools::KubernetesClusterTool / KubernetesProvisioningTool" do
    let!(:cluster) { create(:devops_kubernetes_cluster, :active, account: account) }

    it "lets a devops.kubernetes.read holder list clusters" do
      result = run("kubernetes_list_clusters", {}, user: k8s_reader)

      expect(result[:success]).to be(true)
    end

    it "refuses kubernetes_get_kubeconfig from a read holder — it is the cluster admin credential" do
      result = run("kubernetes_get_kubeconfig", { "cluster_id" => cluster.id }, user: k8s_reader)

      expect_refused(result, "devops.kubernetes.manage")
    end

    it "refuses kubernetes_decommission_cluster from a read holder and the cluster survives" do
      result = nil
      expect {
        result = run("kubernetes_decommission_cluster", { "cluster_id" => cluster.id }, user: k8s_reader)
      }.not_to change { ::Devops::KubernetesCluster.where(account_id: account.id).count }

      expect_refused(result, "devops.kubernetes.manage")
      expect(::Devops::KubernetesCluster.find_by(id: cluster.id)).to be_present
    end
  end

  describe "Ai::Tools::DockerProvisioningTool (floor devops.docker.manage)" do
    it "refuses system_provision_docker_runtime from a read holder" do
      result = run("system_provision_docker_runtime", { "node_instance_id" => SecureRandom.uuid },
                   user: docker_reader)

      expect_refused(result, "devops.docker.manage")
    end

    it "admits a devops.docker.manage holder past the floor" do
      result = run("system_list_managed_docker_hosts", {}, user: docker_manager)

      expect_not_a_permission_error(result)
    end
  end
end
