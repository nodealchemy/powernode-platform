# frozen_string_literal: true

require "rails_helper"

# The REST twin of spec/services/ai/tools/kubeconfig_retrieval_audit_spec.rb.
#
# IMP-4ef95e825a7a audited `kubernetes_get_kubeconfig` at the MCP tool seam and
# made it fail closed. That guard sits on the VERB, not on the credential, and
# this endpoint reaches the same cluster-admin kubeconfig without ever entering
# the MCP layer -- and it is the path the UI's kubeconfig button actually takes
# (frontend/src/features/devops/kubernetes/services/kubernetesApi.ts), so it is
# the route most retrievals go through, not an edge case.
#
# Same two properties as the MCP twin, for the same reasons:
#   * a SUCCESSFUL sensitive read is recorded, not just an anomaly;
#   * it fails CLOSED -- a credential that cannot be recorded is not handed
#     out, and the refusal happens BEFORE the body is rendered.
#
# NEVER LOG THE MATERIAL. The row records that a retrieval happened, by whom,
# for which cluster -- never the kubeconfig itself.
RSpec.describe "kubeconfig retrieval auditing (REST)", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account,
           permissions: %w[devops.kubernetes.read devops.kubernetes.manage])
  end
  let(:headers) { auth_headers_for(user) }

  let(:kubeconfig_material) do
    # Carries a certificate block as well as a token: asserting the absence of
    # a string the fixture never contained proves nothing.
    "apiVersion: v1\nkind: Config\nclusters:\n- cluster:\n    certificate-authority-data: |\n" \
      "      -----BEGIN CERTIFICATE-----\n      MIIBkTCCATegAwIBAgIQZZZZ\n      -----END CERTIFICATE-----\n" \
      "users:\n- name: admin\n  user:\n    token: SUPERSECRET-ADMIN-TOKEN\n"
  end

  let!(:cluster) do
    create(:devops_kubernetes_cluster, :active,
           account: account, encrypted_kubeconfig: kubeconfig_material)
  end

  def retrieve
    get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/kubeconfig",
        headers: headers, as: :json
  end

  # Only the sensitive-access rows. The controller stack writes other audit
  # rows for ordinary request bookkeeping; counting all of them would let this
  # spec pass on a row that has nothing to do with credential disclosure.
  def audit_rows
    AuditLog.where(account: account, action: Ai::SensitiveAccessAudit::ACTION)
  end

  describe "the happy path" do
    it "returns the kubeconfig" do
      retrieve

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "kubeconfig")).to eq(kubeconfig_material)
    end

    it "writes exactly one durable audit row naming the retrieval" do
      expect { retrieve }.to change { audit_rows.count }.by(1)

      row = audit_rows.order(:created_at).last
      expect(row.user_id).to eq(user.id)
      expect(row.account_id).to eq(account.id)
      expect(row.severity).to eq("high")
      expect(row.risk_level).to eq("high")
    end

    it "names the cluster whose credential was released" do
      retrieve

      row = audit_rows.order(:created_at).last
      expect(row.metadata.to_h.dig("context", "cluster_id")).to eq(cluster.id)
    end

    it "records the REST route as the source, distinguishably from the MCP twin" do
      retrieve

      row = audit_rows.order(:created_at).last
      expect(row.metadata.to_h["action_name"]).to eq("devops.kubernetes.kubeconfig")
    end

    it "never writes the credential into the audit row" do
      retrieve

      row = audit_rows.order(:created_at).last
      serialized = row.attributes.to_s
      expect(serialized).not_to include("SUPERSECRET-ADMIN-TOKEN")
      expect(serialized).not_to include("BEGIN CERTIFICATE")
    end
  end

  describe "when the audit row cannot be written (fail closed)" do
    before do
      allow(Ai::SensitiveAccessAudit).to receive(:record).and_return(nil)
    end

    it "refuses the request rather than releasing the credential" do
      retrieve

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("SUPERSECRET-ADMIN-TOKEN")
      expect(response.body).not_to include("BEGIN CERTIFICATE")
    end
  end

  describe "ordering" do
    # A post-hoc audit is theatre: the credential is already out. Pin that the
    # row exists BEFORE the body is rendered by failing the write and checking
    # nothing was disclosed -- and, separately, that a successful retrieval
    # cannot happen without its row.
    it "does not release the kubeconfig when the row is refused" do
      allow(Ai::SensitiveAccessAudit).to receive(:record).and_return(nil)

      expect { retrieve }.not_to(change { audit_rows.count })
      expect(JSON.parse(response.body).dig("data", "kubeconfig")).to be_nil
    end
  end

  describe "authorization is unchanged" do
    it "still refuses a caller without devops.kubernetes.manage" do
      unprivileged = create(:user, account: account, permissions: %w[devops.kubernetes.read])

      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/kubeconfig",
          headers: auth_headers_for(unprivileged), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(audit_rows.count).to eq(0)
    end
  end
end
