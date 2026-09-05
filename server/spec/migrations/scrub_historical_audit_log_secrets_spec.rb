# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260905050000_scrub_historical_audit_log_secrets.rb")

# IMP-fd0340138880. Proves the PROPERTY — after the migration no targeted key
# still holds a payload, and everything else about the row survives — rather
# than the mechanism.
#
# NO REAL PAYLOAD APPEARS HERE. Every value below is an obvious synthetic
# marker. origin publishes to a PUBLIC GitHub mirror and gitleaks allowlists
# spec/ wholesale, so a fixture is exactly the wrong place for a captured
# credential; these strings are shaped only enough to be identifiable.
RSpec.describe ScrubHistoricalAuditLogSecrets do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:placeholder) { described_class::PLACEHOLDER }

  # Marker values. Not credentials — the point of the assertions is that these
  # exact strings stop being present.
  let(:cluster_marker) { "SYNTHETIC-NOT-A-REAL-KUBECONFIG-#{SecureRandom.hex(4)}" }
  let(:token_marker)   { "SYNTHETIC-NOT-A-REAL-TOKEN-#{SecureRandom.hex(4)}" }
  let(:user_marker)    { "synthetic-not-a-real-secret-#{SecureRandom.hex(4)}" }

  def audit!(resource_type:, old_values: {}, new_values: {})
    AuditLog.create!(
      account: account,
      action: "deleted",
      resource_type: resource_type,
      resource_id: SecureRandom.uuid,
      old_values: old_values,
      new_values: new_values
    )
  end

  describe "#up" do
    let!(:cluster_row) do
      audit!(
        resource_type: "Devops::KubernetesCluster",
        old_values: {
          "encrypted_kubeconfig" => cluster_marker,
          "encrypted_server_token" => token_marker,
          "encrypted_agent_token" => token_marker,
          "name" => "prod-cluster",          # NOT a cluster target — must survive
          "status" => "active"
        },
        new_values: { "encrypted_kubeconfig" => cluster_marker }
      )
    end

    let!(:user_row) do
      audit!(
        resource_type: "User",
        old_values: {
          "email" => user_marker,
          "two_factor_secret" => user_marker,
          "email_verification_token" => user_marker,
          "email_verified" => false,                 # deliberately NOT scrubbed
          "email_verified_at" => "2026-01-01T00:00:00Z" # deliberately NOT scrubbed
        }
      )
    end

    # Same key name, different resource_type. `name` is on User's masked set, so
    # a scrub keyed on the key ALONE would rewrite this — the unscoped-WHERE
    # accident this migration is scoped to avoid.
    let!(:unrelated_row) do
      audit!(resource_type: "Ai::Agent", old_values: { "name" => "keep-me", "email" => "keep-me-too" })
    end

    before { migration.up }

    it "leaves no targeted cluster payload in any row" do
      expect(AuditLog.where("old_values::text LIKE ?", "%#{cluster_marker}%")).to be_empty
      expect(AuditLog.where("new_values::text LIKE ?", "%#{cluster_marker}%")).to be_empty
      expect(AuditLog.where("old_values::text LIKE ?", "%#{token_marker}%")).to be_empty
    end

    it "leaves no targeted user payload in any row" do
      expect(AuditLog.where("old_values::text LIKE ?", "%#{user_marker}%")).to be_empty
    end

    it "keeps the key so the audit trail still records THAT the attribute was set" do
      values = cluster_row.reload.old_values

      expect(values.keys).to include("encrypted_kubeconfig", "encrypted_server_token", "encrypted_agent_token")
      expect(values["encrypted_kubeconfig"]).to eq(placeholder)
      expect(values["encrypted_server_token"]).to eq(placeholder)
      expect(values["encrypted_agent_token"]).to eq(placeholder)
    end

    it "preserves the non-secret audit fields of a scrubbed row" do
      row = cluster_row.reload

      expect(row.old_values["name"]).to eq("prod-cluster")
      expect(row.old_values["status"]).to eq("active")
      expect(row.action).to eq("deleted")
      expect(row.account_id).to eq(account.id)
      expect(row.created_at).to be_present
    end

    it "does not touch a same-named key on a different resource_type" do
      expect(unrelated_row.reload.old_values).to eq("name" => "keep-me", "email" => "keep-me-too")
    end

    it "leaves the non-secret User booleans and timestamps alone" do
      values = user_row.reload.old_values

      expect(values["email_verified"]).to be(false)
      expect(values["email_verified_at"]).to eq("2026-01-01T00:00:00Z")
      expect(values["email"]).to eq(placeholder)
      expect(values["two_factor_secret"]).to eq(placeholder)
      expect(values["email_verification_token"]).to eq(placeholder)
    end

    # The chain is why scrub-in-place is safe at all:
    # Audit::LogIntegrityService#build_hash_data covers id/action/resource_type/
    # resource_id/user_id/account_id/ip_address/user_agent/metadata/created_at/
    # sequence_number/previous_hash — old_values and new_values are absent from
    # it. If someone adds them to that payload, this reds, which is the moment
    # this migration's premise stops holding.
    it "leaves the integrity chain intact" do
      before_hash = cluster_row.integrity_hash
      expect(before_hash).to be_present

      expect(cluster_row.reload.integrity_hash).to eq(before_hash)
      expect(Audit::LogIntegrityService.calculate_hash(cluster_row.reload,
                                                       previous_hash: cluster_row.previous_hash))
        .to eq(before_hash)
    end

    # ASSERTS ZERO UPDATES, not merely identical content. A second run that
    # rewrote every row to the same value would leave the jsonb byte-identical
    # and the integrity_hash unchanged (the UPDATE never touches updated_at), so
    # a content comparison passes whether or not the IS DISTINCT FROM guard
    # works. The row count is the only thing that distinguishes them.
    it "is idempotent — a second run rewrites no rows at all" do
      snapshot = AuditLog.order(:id).pluck(:id, :old_values, :new_values, :integrity_hash)

      expect(migration.up).to eq(0)
      expect(AuditLog.order(:id).pluck(:id, :old_values, :new_values, :integrity_hash)).to eq(snapshot)
    end

    # The first run must actually have done work, or "zero on the second run"
    # is satisfied by a migration that never does anything.
    it "reports a non-zero count on the run that did the work" do
      audit!(
        resource_type: "Devops::KubernetesCluster",
        old_values: { "encrypted_kubeconfig" => "SYNTHETIC-SECOND-#{SecureRandom.hex(4)}" }
      )

      expect(migration.up).to be_positive
    end
  end

  describe "#down" do
    it "refuses, because the plaintext is gone by design" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
