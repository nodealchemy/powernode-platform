# frozen_string_literal: true

require "rails_helper"

# IMP-01a08809. Auditable redacts on ITS OWN path — it calls redact_audit_values
# and only then hands the result to AuditLog.log_action — so every OTHER writer
# of audit_logs reached the table unredacted:
#
#   Audit::LoggingService#log -> AuditLog.log_action   wrote old_values/new_values
#                                                      verbatim (only the auth
#                                                      path's request_params was
#                                                      sanitized)
#   AuditLog.create!                                   58 direct call sites,
#                                                      bypassing log_action
#                                                      entirely — one of them
#                                                      (site_settings_controller)
#                                                      passes `.attributes`
#                                                      wholesale
#   AuditLogging#resource_attributes_for_logging       redacted by a hand-written
#                                                      8-name denylist that named
#                                                      no encrypted column and no
#                                                      filter_attributes entry
#
# Rails `encrypts` installs an attribute TYPE, so `.attributes` hands back
# DECRYPTED plaintext: any of those paths wrote the raw 2FA secret / API key
# into a durable, chain-hashed table served by GET /api/v1/audit_logs to anyone
# holding `audit.read`.
#
# The fix guards the DECISION ("what values land in an audit row") rather than
# each mechanism: a before_validation on AuditLog itself, which every writer —
# present, direct, and future — passes through. These examples therefore assert
# through the WRITERS, never by calling the callback directly.
#
# SECRET-HANDLING: every disclosure assertion is on the ABSENCE of a synthetic
# plaintext. `discloses?` returns a bare boolean, so neither RSpec's differ nor
# a failure line can print secret material. Do not "improve" these by asserting
# on the value itself.
#
# Redaction assertions are paired with SURVIVAL assertions: a mutant that
# redacts everything would destroy the audit trail while passing every absence
# check.
RSpec.describe "AuditLog write-seam redaction" do
  # Namespaced rather than bare constants: a constant assigned inside an RSpec
  # block lands on Object, which is the duplicate-constant-clobber shape that
  # produces order-dependent flakes across this shared suite.
  module SyntheticSeamProbe
    TOTP_SECRET   = "zz-synthetic-seam-probe-totp-secret"
    RESET_DIGEST  = "zz-synthetic-seam-probe-reset-digest"
    BENIGN_STATUS = "active"
    FILTERED      = Auditable::REDACTED_PLACEHOLDER
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Returns a bare boolean; never returns or raises with the value in it.
  def discloses?(values, secret)
    return false if values.blank?

    values.to_json.include?(secret)
  end

  def expect_no_disclosure(row, *secrets)
    secrets.each do |secret|
      expect(discloses?(row.old_values, secret)).to be(false),
        "old_values disclosed a secret attribute"
      expect(discloses?(row.new_values, secret)).to be(false),
        "new_values disclosed a secret attribute"
    end
  end

  describe "AuditLog.create! — the direct path 58 call sites use" do
    it "redacts an encrypted column handed over as raw .attributes" do
      user.update!(two_factor_secret: SyntheticSeamProbe::TOTP_SECRET)

      row = AuditLog.create!(
        account: account, user: user,
        action: "delete", resource_type: "User", resource_id: user.id,
        source: "admin_panel",
        old_values: user.reload.attributes
      )

      expect_no_disclosure(row.reload, SyntheticSeamProbe::TOTP_SECRET)
      expect(row.old_values["two_factor_secret"]).to eq(SyntheticSeamProbe::FILTERED)
    end

    it "redacts a filter_attributes column that carries no `encrypts`" do
      user.update!(reset_token_digest: SyntheticSeamProbe::RESET_DIGEST)

      row = AuditLog.create!(
        account: account, user: user,
        action: "update", resource_type: "User", resource_id: user.id,
        source: "api",
        new_values: user.reload.attributes
      )

      expect_no_disclosure(row.reload, SyntheticSeamProbe::RESET_DIGEST)
      expect(row.new_values["reset_token_digest"]).to eq(SyntheticSeamProbe::FILTERED)
    end

    it "leaves benign attributes intact — redacting everything is not a fix" do
      row = AuditLog.create!(
        account: account, user: user,
        action: "update", resource_type: "User", resource_id: user.id,
        source: "api",
        new_values: user.reload.attributes
      )

      expect(row.reload.new_values["status"]).to eq(SyntheticSeamProbe::BENIGN_STATUS)
      expect(row.new_values["id"]).to eq(user.id)
    end
  end

  describe "AuditLog.log_action — the Audit::LoggingService path" do
    it "redacts values the caller passes through Audit::LoggingService" do
      user.update!(two_factor_secret: SyntheticSeamProbe::TOTP_SECRET)

      row = Audit::LoggingService.instance.log(
        action: "update",
        resource: user.reload,
        user: user,
        account: account,
        source: "api",
        new_values: user.attributes
      )

      expect(row).to be_present, "no audit row was written — the oracle would pass vacuously"
      expect_no_disclosure(row.reload, SyntheticSeamProbe::TOTP_SECRET)
    end
  end

  describe "an unresolvable resource_type" do
    # Audit::LoggingService and AuditLogging both synthesize OpenStruct dummy
    # resources whose class NAME ("API", "Webhook") constantizes to nothing.
    # The seam must still apply the always-redacted floor rather than raise —
    # a redaction pass that blows up would take the audit write down with it.
    it "still redacts the always-redacted floor and does not raise" do
      row = nil

      expect {
        row = AuditLog.create!(
          account: account, user: user,
          action: "create", resource_type: "Webhook", resource_id: "stripe",
          source: "api",
          new_values: { "password_digest" => SyntheticSeamProbe::RESET_DIGEST,
                        "status" => SyntheticSeamProbe::BENIGN_STATUS }
        )
      }.not_to raise_error

      expect_no_disclosure(row.reload, SyntheticSeamProbe::RESET_DIGEST)
      expect(row.new_values["status"]).to eq(SyntheticSeamProbe::BENIGN_STATUS)
    end

    it "passes a non-Hash value column through untouched" do
      row = AuditLog.create!(
        account: account, user: user,
        action: "create", resource_type: "Webhook", resource_id: "stripe",
        source: "api",
        new_values: [ "a", "b" ]
      )

      expect(row.reload.new_values).to eq([ "a", "b" ])
    end
  end

  describe "AuditLogging#resource_attributes_for_logging" do
    # The controller-side snapshot. Its own chain (log_resource_* / log_user_*)
    # has no callers today, which is why the stale denylist was latent — but the
    # concern IS included by 60+ controllers, so the method is one call away from
    # live. Pinned here rather than left to the row-level seam because it carries
    # a trap the seam cannot see: the method appends computed `name` / `email`
    # readers, and those are `encrypts` columns on User. Appending them AFTER the
    # filter writes the plaintext back over the mask.
    let(:snapshotter) do
      Class.new do
        include AuditLogging
        public :resource_attributes_for_logging
      end.new
    end

    it "redacts the computed readers it appends, not just the raw columns" do
      user.update!(two_factor_secret: SyntheticSeamProbe::TOTP_SECRET)
      values = snapshotter.resource_attributes_for_logging(user.reload)

      expect(discloses?(values, SyntheticSeamProbe::TOTP_SECRET)).to be(false),
        "the attribute snapshot disclosed a secret attribute"
      expect(values["two_factor_secret"]).to eq(SyntheticSeamProbe::FILTERED)
      expect(values["email"]).to eq(SyntheticSeamProbe::FILTERED)
      expect(values["name"]).to eq(SyntheticSeamProbe::FILTERED)
    end

    it "keeps the benign computed reader it exists to add" do
      values = snapshotter.resource_attributes_for_logging(user.reload)

      expect(values["status"]).to eq(SyntheticSeamProbe::BENIGN_STATUS)
    end

    it "returns {} for a resource with no attributes, as before" do
      dummy = OpenStruct.new(id: "x")

      expect(snapshotter.resource_attributes_for_logging(dummy)).to eq({})
    end
  end

  describe "idempotence with Auditable's own pre-redaction" do
    # Auditable redacts BEFORE calling log_action, so its rows arrive already
    # masked. Running the seam over them must be a no-op, not a second pass
    # that mangles the placeholder.
    it "leaves an already-redacted placeholder alone" do
      row = AuditLog.create!(
        account: account, user: user,
        action: "update", resource_type: "User", resource_id: user.id,
        source: "system",
        new_values: { "two_factor_secret" => SyntheticSeamProbe::FILTERED }
      )

      expect(row.reload.new_values["two_factor_secret"]).to eq(SyntheticSeamProbe::FILTERED)
    end
  end
end
