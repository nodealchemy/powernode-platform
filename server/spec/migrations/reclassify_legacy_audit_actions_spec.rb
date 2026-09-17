# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260917010000_reclassify_legacy_audit_actions.rb")

# IMP-85fb47438be6. Proves the PROPERTY the operator ruling requires: a legacy
# row is never renamed or re-chained, and exactly one new correction row is
# appended per legacy row, chained normally like any other write, with the
# authoritative payload inside the hashed `metadata` column (review F1).
RSpec.describe ReclassifyLegacyAuditActions do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Seeds a row AS IT EXISTED before this cleanup — a legacy action written
  # before AuditActions.all_actions stopped accepting it. Built the same way
  # the sibling scrub-migration spec builds pre-existing rows: create! with a
  # valid action, then rewrite the column directly (update_columns skips
  # validation, so it can hold a value the current allowlist rejects), mirroring
  # a row that predates this change rather than one written under it.
  def legacy_row!(legacy_action)
    row = AuditLog.create!(
      account: account,
      user: user,
      action: "deleted",
      resource_type: "Ai::Agent",
      resource_id: SecureRandom.uuid
    )
    row.update_columns(action: legacy_action)
    row.reload
  end

  # F4 (review, 2026-09-17): every canonical target the mapping writes must
  # itself be a currently-valid action, or a typo'd target would write a
  # permanent wrong correction row that #down cannot undo (it unconditionally
  # refuses). Covers all 28 pairs (20 AuditActions::LEGACY_ACTIONS ones + the
  # 8 ai_agent_team.* -> ai.agent_team.* rename pairs).
  it "maps every legacy action to a currently-valid canonical action" do
    expect(described_class::LEGACY_TO_CANONICAL.values.uniq - AuditActions.all_actions).to be_empty
  end

  describe "#up" do
    context "with no legacy-named rows" do
      it "is a no-op" do
        create(:audit_log, account: account, action: "create")

        expect { expect(migration.up).to eq(0) }.not_to change(AuditLog, :count)
      end
    end

    context "with legacy-named rows" do
      let!(:agents_row) { legacy_row!("ai_agents.index") }
      let!(:messages_row) { legacy_row!("ai_messages.edit_content") }
      let!(:agent_team_row) { legacy_row!("ai_agent_team.member_added") }
      let!(:unrelated_row) { create(:audit_log, account: account, action: "create") }

      it "leaves the legacy rows' action untouched" do
        migration.up

        expect(agents_row.reload.action).to eq("ai_agents.index")
        expect(messages_row.reload.action).to eq("ai_messages.edit_content")
        expect(agent_team_row.reload.action).to eq("ai_agent_team.member_added")
      end

      it "does not touch the legacy rows' integrity_hash" do
        before_agents_hash = agents_row.integrity_hash
        before_messages_hash = messages_row.integrity_hash
        before_agent_team_hash = agent_team_row.integrity_hash

        migration.up

        expect(agents_row.reload.integrity_hash).to eq(before_agents_hash)
        expect(messages_row.reload.integrity_hash).to eq(before_messages_hash)
        expect(agent_team_row.reload.integrity_hash).to eq(before_agent_team_hash)
      end

      it "appends exactly one correctly-shaped correction row per legacy row" do
        expect { migration.up }.to change(AuditLog, :count).by(3)

        agents_correction = AuditLog.find_by(
          action: "audit.action_reclassified",
          resource_type: "AuditLog",
          resource_id: agents_row.id
        )
        messages_correction = AuditLog.find_by(
          action: "audit.action_reclassified",
          resource_type: "AuditLog",
          resource_id: messages_row.id
        )
        agent_team_correction = AuditLog.find_by(
          action: "audit.action_reclassified",
          resource_type: "AuditLog",
          resource_id: agent_team_row.id
        )

        expect(agents_correction).to be_present
        expect(agents_correction.old_values).to eq("action" => "ai_agents.index")
        expect(agents_correction.new_values).to eq("action" => "ai.agents.read")
        expect(agents_correction.account_id).to eq(account.id)

        expect(messages_correction).to be_present
        expect(messages_correction.old_values).to eq("action" => "ai_messages.edit_content")
        expect(messages_correction.new_values).to eq("action" => "ai.messages.edit_content")

        expect(agent_team_correction).to be_present
        expect(agent_team_correction.old_values).to eq("action" => "ai_agent_team.member_added")
        expect(agent_team_correction.new_values).to eq("action" => "ai.agent_team.member_added")
      end

      # F1 (review, 2026-09-17): the authoritative pair lives in `metadata`,
      # which build_hash_data DOES cover — not merely in old_values/new_values,
      # which it does not. This is the spec that reddens if the payload ever
      # moves back out of metadata: it asserts metadata directly rather than
      # inferring it from old_values/new_values (which still carry an
      # identical, but non-authoritative, duplicate — see the next example).
      it "carries the authoritative {from, to} pair in metadata, not just old_values/new_values" do
        migration.up

        correction = AuditLog.find_by(action: "audit.action_reclassified", resource_id: agents_row.id)

        expect(correction.metadata).to eq(
          "reclassified_action_from" => "ai_agents.index",
          "reclassified_action_to" => "ai.agents.read"
        )
      end

      it "leaves old_values/new_values as a readable, non-authoritative duplicate" do
        migration.up

        correction = AuditLog.find_by(action: "audit.action_reclassified", resource_id: agents_row.id)

        expect(correction.old_values).to eq("action" => "ai_agents.index")
        expect(correction.new_values).to eq("action" => "ai.agents.read")
      end

      # Demonstrates WHY the payload must be in metadata rather than
      # old_values/new_values: build_hash_data hashes metadata but not
      # old_values/new_values, so tampering with the latter (in place, the
      # same way 20260905050000_scrub_historical_audit_log_secrets.rb rewrites
      # those same two columns on other sealed rows) leaves the chain reading
      # as intact, while tampering with metadata breaks it.
      it "is tamper-evident on metadata but not on the old_values/new_values duplicate" do
        migration.up
        correction = AuditLog.find_by(action: "audit.action_reclassified", resource_id: agents_row.id)
        before_hash = correction.integrity_hash

        correction.update_columns(old_values: { "action" => "tampered" }, new_values: { "action" => "tampered" })
        expect(Audit::LogIntegrityService.verify_entry(correction.reload)).to include(valid: true)
        expect(correction.integrity_hash).to eq(before_hash)

        correction.update_columns(metadata: { "reclassified_action_from" => "tampered", "reclassified_action_to" => "tampered" })
        expect(Audit::LogIntegrityService.verify_entry(correction.reload)[:valid]).to be false
      end

      it "chains the new correction rows normally (present integrity_hash and sequence_number)" do
        migration.up

        correction = AuditLog.find_by(action: "audit.action_reclassified", resource_id: agents_row.id)

        expect(correction.integrity_hash).to be_present
        expect(correction.sequence_number).to be_present
        expect(Audit::LogIntegrityService.verify_entry(correction)).to include(valid: true)
      end

      it "does not create a correction row for an unrelated, already-canonical row" do
        migration.up

        expect(
          AuditLog.where(action: "audit.action_reclassified", resource_id: unrelated_row.id)
        ).to be_empty
      end

      it "returns the number of correction rows it created" do
        expect(migration.up).to eq(3)
      end

      it "is idempotent — a second run corrects nothing further" do
        migration.up

        expect { expect(migration.up).to eq(0) }.not_to change(AuditLog, :count)
      end
    end
  end

  describe "#down" do
    it "refuses, because no row was renamed and correction rows extend the chain" do
      expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
end
