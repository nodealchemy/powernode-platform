# frozen_string_literal: true

require "rails_helper"

# c13-2 batch C-E (the last core batch). delete_gitea_action_secret and
# delete_gitea_user_token are HUMAN-ONLY: they park for a person's own session
# whoever calls, and run only as the person who confirms. delete_gitea_workflow_run
# and kubernetes_decommission_cluster are require_approval. Every example asserts
# the row or the remote call as well as the envelope.
RSpec.describe "c13-2 batch C-E destructive verbs park", type: :service do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) } # first user: account owner
  let(:ci_user) { create(:user, account: account, permissions: %w[devops.ci.write]) }
  let(:k8s_user) { create(:user, account: account, permissions: %w[devops.kubernetes.manage]) }
  let(:person) do
    create(:user, account: account, permissions: %w[ai.autonomy.approve ai.agents.read devops.ci.write devops.kubernetes.manage])
  end
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read devops.ci.read devops.kubernetes.read]) }

  let(:gitea_provider) do
    ::Devops::GitProvider.find_or_create_by!(account: account, provider_type: "gitea") do |p|
      p.name = "Gitea"
      p.slug = "gitea-#{SecureRandom.hex(4)}"
      p.api_base_url = "https://git.example.com"
      p.capabilities = { "actions" => true }
    end
  end
  let!(:credential) do
    create(:git_provider_credential, account: account, provider: gitea_provider, is_active: true, is_default: true)
  end
  let(:client) { instance_double(Devops::Git::GiteaApiClient) }

  before { allow(::Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client) }

  after { ::Mcp::Principal.reset! }

  def run(tool_class, params = {}, user:, agent: nil, **rest)
    tool = tool_class.new(account: account, user: user, agent: agent)
    tool.call_origin = "mcp_oauth"
    tool.execute(params: params.merge(rest).with_indifferent_access)
  end

  def gitea(params = {}, user: ci_user, agent: nil, **rest)
    run(Ai::Tools::GiteaActionsTool, params.merge(rest), user: user, agent: agent)
  end

  def expect_parked(result, category)
    expect(result).to include(success: true)
    expect(result[:data]).to include(pending: true)
    operation = Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
    expect(operation.action_category).to eq(category)
    expect(operation.executor_class).to eq("Ai::Executors::DeferredToolCall")
    expect(Ai::ApprovalRequest.find(result[:data][:approval_request_id]).requires_human_session?).to be(true)
    operation
  end

  def confirm!(parked, as: person, expect_ok: true)
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
    decided = Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                                   .approve(request: request, approver: as,
                                                            origin: Ai::ApprovalDecision::REST_SESSION)
    expect(decided).to be(true) if expect_ok
    Ai::DeferredOperation.find(parked[:data][:deferred_operation_id]).reload
  end

  # [action, params, category, client method]
  GITEA_HUMAN_ONLY = [
    [ "delete_gitea_action_secret", { owner: "o", repo: "r", secret_name: "DEPLOY_KEY" },
      "gitea.action_secret.delete", :delete_action_secret ],
    [ "delete_gitea_user_token", { name_or_id: "ci-token-7" }, "gitea.user_token.delete", :delete_user_token ]
  ].freeze

  GITEA_HUMAN_ONLY.each do |action, params, category, client_method|
    describe "#{action} (human_only)" do
      it "parks for a person's own session and never reaches Gitea" do
        expect(client).not_to receive(client_method)

        parked = gitea({ action: action }.merge(params))

        expect_parked(parked, category)
        expect(parked[:data]).to include(requires_human_session: true)
      end

      it "refuses an agent principal with no user, and parks nothing" do
        expect(client).not_to receive(client_method)

        result = gitea({ action: action }.merge(params), user: nil, agent: create(:ai_agent, account: account))

        expect(result[:success]).to be(false)
        expect(Ai::DeferredOperation.count).to eq(0)
      end

      it "refuses a caller without devops.ci.write, and parks nothing" do
        result = gitea({ action: action }.merge(params), user: reader)

        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/permission denied: devops.ci.write/)
        expect(Ai::DeferredOperation.count).to eq(0)
      end

      it "runs as the person who confirms it in their own session" do
        parked = gitea({ action: action }.merge(params))
        # The card redacts a secret-named key; the replay still receives the real value.
        expect(client).to receive(client_method).with(*params.values).and_return({ success: true })

        operation = confirm!(parked)

        expect(operation.status).to eq("completed")
        expect(operation.result.with_indifferent_access).to include(success: true)
      end

      it "does not run when the confirming person lacks devops.ci.write" do
        parked = gitea({ action: action }.merge(params))
        approver = create(:user, account: account, permissions: %w[ai.autonomy.approve ai.agents.read])
        expect(client).not_to receive(client_method)

        confirm!(parked, as: approver, expect_ok: false)
      end
    end
  end

  describe "what the approval card carries (token and secret handling)" do
    it "redacts a secret's name on the card but shows the repo, and shows a token's name or id" do
      secret = gitea(action: "delete_gitea_action_secret", owner: "o", repo: "r", secret_name: "DEPLOY_KEY")
      token = gitea(action: "delete_gitea_user_token", name_or_id: "ci-token-7")
      shown = ->(parked) { Ai::ApprovalRequest.find(parked[:data][:approval_request_id]).request_data.to_json }

      expect(shown.call(secret)).to include('"repo":"r"').and include("[FILTERED]")
      expect(shown.call(secret)).not_to include("DEPLOY_KEY")
      expect(shown.call(token)).to include("ci-token-7")
    end

    it "names the target but never a token or secret value" do
      parked = gitea(action: "delete_gitea_user_token", name_or_id: "ci-token-7")
      request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])

      expect(request.request_data.to_json).not_to match(/sha1|"token":\s*"[0-9a-f]{20,}/i)
      expect(request.request_data.to_json).to include("delete_gitea_user_token")
    end
  end

  describe "delete_gitea_workflow_run" do
    let(:params) { { action: "delete_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" } }

    it "parks, and never reaches Gitea" do
      expect(client).not_to receive(:delete_workflow_run)

      expect_parked(gitea(params), "gitea.workflow_run.delete")
    end

    it "deletes on approval, as the original caller" do
      parked = gitea(params)
      expect(client).to receive(:delete_workflow_run).with("o", "r", "42").and_return({ success: true })

      expect(confirm!(parked).status).to eq("completed")
    end

    it "refuses the replay when devops.ci.write was revoked after parking" do
      parked = gitea(params)
      RolePermission.where(role_id: ci_user.roles.select(:id), permission_name: "devops.ci.write").delete_all
      expect(client).not_to receive(:delete_workflow_run)

      operation = confirm!(parked)

      expect(operation.reload.result.with_indifferent_access).to include(success: false)
    end

    it "refuses a caller without devops.ci.write, and parks nothing" do
      result = gitea(params, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied: devops.ci.write/)
      expect(Ai::DeferredOperation.count).to eq(0)
    end
  end

  describe "kubernetes_decommission_cluster" do
    let!(:cluster) { create(:devops_kubernetes_cluster, account: account) }
    let(:params) { { action: "kubernetes_decommission_cluster", cluster_id: cluster.id } }

    def k8s(p, user: k8s_user) = run(Ai::Tools::KubernetesProvisioningTool, p, user: user)

    it "parks, leaving the cluster in place" do
      expect_parked(k8s(params), "kubernetes.cluster.decommission")
      expect(Devops::KubernetesCluster.where(id: cluster.id)).to exist
    end

    it "decommissions on approval, as the original caller" do
      parked = k8s(params)

      expect(confirm!(parked).status).to eq("completed")
      expect(Devops::KubernetesCluster.where(id: cluster.id)).not_to exist
    end

    it "refuses the replay, keeping the cluster, when devops.kubernetes.manage was revoked after parking" do
      parked = k8s(params)
      RolePermission.where(role_id: k8s_user.roles.select(:id), permission_name: "devops.kubernetes.manage").delete_all

      confirm!(parked)

      expect(Devops::KubernetesCluster.where(id: cluster.id)).to exist
    end

    it "refuses a caller without devops.kubernetes.manage, and parks nothing" do
      result = k8s(params, user: reader)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/permission denied: devops.kubernetes.manage/)
      expect(Ai::DeferredOperation.count).to eq(0)
      expect(Devops::KubernetesCluster.where(id: cluster.id)).to exist
    end
  end
end
