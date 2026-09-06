# frozen_string_literal: true

require "rails_helper"

# IMP-4ef95e825a7a. `kubernetes_get_kubeconfig` hands back the cluster-admin
# kubeconfig — root on every workload in the cluster — and its only record was
# a Rails.logger.info line. There was no durable, queryable answer to "who
# retrieved this credential, and when".
#
# The seam this pins deliberately differs from the two audit rows base_tool
# already writes (canonical-principal refusal, undeclared-action sighting) in
# two ways, both required by the operator direction on this task:
#   * those record ANOMALIES and this records a SUCCESSFUL sensitive read;
#   * those fail OPEN (rescue + log, so telemetry never breaks a call) while
#     this must fail CLOSED — a credential that cannot be recorded is not
#     handed out. The refusal therefore belongs at the gate, BEFORE the
#     executor runs; refusing after the fact would be theatre, the kubeconfig
#     having already been released.
#
# NEVER LOG THE MATERIAL. The row records that a retrieval happened, by whom,
# for which cluster — never the kubeconfig itself.
RSpec.describe "kubeconfig retrieval auditing" do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:tool)    { Ai::Tools::KubernetesProvisioningTool.new(account: account, agent: nil, user: user) }

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
    tool.execute(params: { action: "kubernetes_get_kubeconfig", cluster_id: cluster.id })
  end

  def audit_rows
    AuditLog.where(account: account).where.not(action: %w[
      mcp.tools.undeclared_action mcp.tools.canonical_principal_refused
    ])
  end

  describe "the happy path" do
    it "returns the kubeconfig" do
      result = retrieve
      expect(result[:success]).to be(true)
      expect(result[:kubeconfig]).to eq(kubeconfig_material)
    end

    it "writes exactly one durable audit row naming the retrieval" do
      expect { retrieve }.to change { audit_rows.count }.by(1)

      row = audit_rows.order(:created_at).last
      # One registered action name covers every audited verb, because
      # AuditLog#action is allowlisted by AuditActions — a per-verb string
      # would mean registering each one. The verb is in metadata, which is
      # what makes the row queryable per-action.
      expect(row.action).to eq("mcp.tools.sensitive_access")
      expect(row.metadata["action_name"]).to eq("kubernetes_get_kubeconfig")
      expect(row.account_id).to eq(account.id)
    end

    it "attributes the row to the principal that retrieved it" do
      retrieve
      row = audit_rows.order(:created_at).last

      expect(row.user_id).to eq(user.id),
        "the whole point of this row is WHO retrieved the credential"
      expect(row.metadata.dig("context", "cluster_id")).to eq(cluster.id),
        "and for WHICH cluster — read the field, not the serialized blob, or " \
        "an id appearing anywhere in the principal payload would satisfy this"
    end

    it "rates the row as a high-risk event, not routine telemetry" do
      retrieve
      row = audit_rows.order(:created_at).last
      expect(%w[high critical]).to include(row.risk_level)
    end

    # The reason this file exists in the same family as the audit_logs secret
    # backfill: that line was crossed before.
    it "NEVER stores the credential anywhere on the row" do
      retrieve
      row = audit_rows.order(:created_at).last

      serialized = row.attributes.to_s
      expect(serialized).not_to include("SUPERSECRET-ADMIN-TOKEN")
      expect(serialized).not_to include(kubeconfig_material)
      expect(serialized).not_to include("BEGIN CERTIFICATE")
    end
  end

  describe "the refusal arm — fail CLOSED" do
    before do
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))
    end

    it "does not hand out a kubeconfig that could not be recorded" do
      result = retrieve

      expect(result[:success]).to be(false)
      expect(result[:kubeconfig]).to be_nil,
        "a credential released despite an unwritable audit row is exactly the hole this closes"
    end

    it "says why it refused" do
      expect(retrieve[:error].to_s.downcase).to match(/audit/)
    end

    # Deliberately NOT "writes no row": AuditLog.create! is stubbed to raise
    # globally in this context, so no code anywhere could write one and that
    # example would pass with the production fix fully reverted. What is worth
    # asserting is that the tool body never ran.
    it "never reaches the tool body, so the credential is never read" do
      expect(Rails.logger).not_to receive(:info).with(/kubeconfig retrieved/)
      retrieve
    end
  end

  # THE CENTRAL CLAIM OF THE DESIGN, and the one the refusal examples cannot
  # reach: the row is a PRECONDITION, not a record written alongside. Moving
  # the audit call after `call(params)` and discarding the result still
  # satisfies every assertion above, because the refusal envelope replaces the
  # return value either way and this action is a pure read. These pin the
  # ordering directly.
  describe "ordering — the row precedes the retrieval" do
    it "writes the audit row BEFORE the tool body runs" do
      sequence = []

      allow(AuditLog).to receive(:create!).and_wrap_original do |orig, *args, **kwargs|
        sequence << :audit_row
        orig.call(*args, **kwargs)
      end
      allow(Rails.logger).to receive(:info).and_wrap_original do |orig, *args|
        sequence << :tool_body if args.first.to_s.include?("kubeconfig retrieved")
        orig.call(*args)
      end

      retrieve

      expect(sequence).to eq(%i[audit_row tool_body]),
        "a row written after the body means the credential was read before it " \
        "was recorded, which is the hole this task closes"
    end
  end

  describe "scope of the seam" do
    it "does not audit the sibling action on the SAME class" do
      other_cluster = create(:devops_kubernetes_cluster, account: account)
      expect {
        tool.execute(params: { action: "kubernetes_decommission_cluster", cluster_id: other_cluster.id })
      }.not_to change { audit_rows.count },
        "a class-wide audit: true slip would be invisible to a check that uses " \
        "a different tool class"
    end

    it "does not audit actions that did not opt in" do
      other = Ai::Tools::KubernetesClusterTool.new(account: account, agent: nil, user: user)

      expect {
        other.execute(params: { action: "kubernetes_list_clusters" })
      }.not_to change { audit_rows.count }
    end
  end
end
