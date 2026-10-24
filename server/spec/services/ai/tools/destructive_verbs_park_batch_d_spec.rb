# frozen_string_literal: true

require "rails_helper"

# c13-2 batch C-D. The eight docker delete verbs act on remote Docker hosts and
# Swarm clusters. Each was declared `destructive: true` but armed no gate, so a
# user principal reached the daemon directly. Each now parks behind the autonomy
# gate as a require_approval deferred tool call; the daemon is reached only on the
# replay of an approval, as the ORIGINAL caller, with the tool's own permission
# ladder and the account-scoped host/cluster lookup re-run first.
RSpec.describe "c13-2 batch C-D docker delete verbs park", type: :service do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: account owner
  let(:caller_user) do
    create(:user, account: account,
                  permissions: %w[devops.docker.read devops.docker.manage devops.swarm.read devops.swarm.manage])
  end
  let(:confirmer) { create(:user, account: account, permissions: %w[ai.autonomy.approve ai.agents.read]) }
  let(:reader) { create(:user, account: account, permissions: %w[devops.docker.read devops.swarm.read]) }
  let!(:host) { create(:devops_docker_host, :connected, account: account) }
  let!(:cluster) { create(:devops_swarm_cluster, account: account) }

  after { ::Mcp::Principal.reset! }

  def run(tool_class, params = {}, user: caller_user, **rest)
    tool = tool_class.new(account: account, user: user)
    tool.call_origin = "mcp_oauth"
    tool.execute(params: params.merge(rest).with_indifferent_access)
  end

  def expect_parked(result, category)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
    expect(operation.action_category).to eq(category)
    expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
    # destructive: true makes the approver a person in their own session.
    expect(Ai::ApprovalRequest.find(result[:data][:approval_request_id]).requires_human_session?).to be(true)
    operation
  end

  def confirm!(parked, as: confirmer)
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
    Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                         .approve(request: request, approver: as,
                                                  origin: Ai::ApprovalDecision::REST_SESSION)
    Ai::DeferredOperation.find(parked[:data][:deferred_operation_id]).reload
  end

  # [tool, action, params, category, manager class, manager method, required permission]
  VERBS = [
    [ Ai::Tools::DockerClusterTool, "docker_delete_config", { cluster_id: :cluster, config_id: "cfg1" },
      "docker.config.delete", "Devops::Docker::SecretManager", :remove_config, "devops.swarm.manage" ],
    [ Ai::Tools::DockerClusterTool, "docker_delete_secret", { cluster_id: :cluster, secret_id: "sec1" },
      "docker.secret.delete", "Devops::Docker::SecretManager", :remove, "devops.swarm.manage" ],
    [ Ai::Tools::DockerContainerTool, "docker_delete_container", { host_id: :host, container_id: "c1" },
      "docker.container.delete", "Devops::Docker::ContainerManager", :remove_container, "devops.docker.manage" ],
    [ Ai::Tools::DockerImageTool, "docker_delete_image", { host_id: :host, image_id: "i1" },
      "docker.image.delete", "Devops::Docker::ImageManager", :remove_image, "devops.docker.manage" ],
    [ Ai::Tools::DockerNetworkVolumeTool, "docker_delete_network", { cluster_id: :cluster, network_id: "n1" },
      "docker.network.delete", "Devops::Docker::NetworkManager", :remove, "devops.swarm.manage" ],
    [ Ai::Tools::DockerNetworkVolumeTool, "docker_delete_volume", { cluster_id: :cluster, volume_name: "v1" },
      "docker.volume.delete", "Devops::Docker::VolumeManager", :remove, "devops.swarm.manage" ],
    [ Ai::Tools::DockerServiceTool, "docker_delete_service", { cluster_id: :cluster, service_id: "s1" },
      "docker.service.delete", "Devops::Docker::ServiceManager", :remove_service, "devops.swarm.manage" ],
    [ Ai::Tools::DockerStackTool, "docker_delete_stack", { cluster_id: :cluster, stack_id: "st1" },
      "docker.stack.delete", "Devops::Docker::StackManager", :remove_stack, "devops.swarm.manage" ]
  ].freeze

  def resolved(params)
    params.transform_values { |v| v == :host ? host.id : (v == :cluster ? cluster.id : v) }
  end

  VERBS.each do |tool_class, action, params, category, manager, method, permission|
    describe action do
      it "parks, and never reaches the daemon" do
        expect_any_instance_of(manager.constantize).not_to receive(method)

        operation = expect_parked(run(tool_class, { action: action }.merge(resolved(params))), category)

        # What the parked request carries about the target: the caller's params verbatim
        # (a secret-named key is stored redacted yet replays intact: see the secret example).
        expect(operation.read_attribute(:params).dig("tool_params"))
          .to include(resolved(params).except(:secret_id).stringify_keys)
      end

      it "is refused for a caller without #{permission}, and parks nothing" do
        expect_any_instance_of(manager.constantize).not_to receive(method)

        result = run(tool_class, { action: action }.merge(resolved(params)), user: reader)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/permission denied: #{Regexp.escape(permission)}/)
        expect(Ai::DeferredOperation.count).to eq(0)
        expect(Ai::ApprovalRequest.count).to eq(0)
      end
    end
  end

  it "keeps a secret id off the approval card and the model's reader, but replays it verbatim" do
    parked = run(Ai::Tools::DockerClusterTool, action: "docker_delete_secret", cluster_id: cluster.id, secret_id: "sec-id-1")
    operation = expect_parked(parked, "docker.secret.delete")
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])

    expect(request.request_data.to_json).not_to include("sec-id-1")
    expect(operation.params.to_json).not_to include("sec-id-1")
    seen = nil
    allow_any_instance_of(Devops::Docker::SecretManager).to receive(:remove) { |_, id| seen = id; { success: true } }

    confirm!(parked)

    expect(seen).to eq("sec-id-1")
  end

  describe "approve and replay (docker_delete_container)" do
    let!(:container) { create(:devops_docker_container, :stopped, docker_host: host) }
    let(:manager) { instance_double(Devops::Docker::ContainerManager) }

    def park
      run(Ai::Tools::DockerContainerTool,
          action: "docker_delete_container", host_id: host.id, container_id: container.id)
    end

    it "reaches the daemon only after a person approves, as the original caller" do
      parked = park
      expect_parked(parked, "docker.container.delete")
      allow(Devops::Docker::ContainerManager).to receive(:new).and_return(manager)
      expect(manager).to receive(:remove_container).with(container, force: false)

      operation = confirm!(parked)

      expect(operation.status).to eq("completed")
      expect(operation.result.with_indifferent_access).to include(success: true, message: "Container removed")
    end

    it "refuses the replay, never reaching the daemon, when devops.docker.manage was revoked after parking" do
      parked = park
      RolePermission.where(role_id: caller_user.roles.select(:id), permission_name: "devops.docker.manage").delete_all
      expect(Devops::Docker::ContainerManager).not_to receive(:new)

      operation = confirm!(parked)

      expect(operation.reload.result.with_indifferent_access[:error]).to match(/permission denied: devops.docker.manage/)
    end

    it "re-scopes the host to the account at replay: a host of another account is not found" do
      parked = park
      host.update_columns(account_id: create(:account).id)
      expect(Devops::Docker::ContainerManager).not_to receive(:new)

      operation = confirm!(parked)

      expect(operation.reload.result.with_indifferent_access).to include(success: false)
    end
  end
end
