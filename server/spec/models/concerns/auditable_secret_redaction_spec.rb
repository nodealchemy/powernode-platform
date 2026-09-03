# frozen_string_literal: true

require "rails_helper"

# Rails `encrypts` installs an attribute TYPE, so `attributes` and
# `saved_changes` hand back DECRYPTED plaintext. Auditable feeds both of those
# straight into `audit_logs.old_values` / `new_values`, which are durable,
# chain-hashed rows served by GET /api/v1/audit_logs to anyone holding
# `audit.read`. Without redaction, creating or updating a credential writes the
# raw API key / OAuth token — and updating a User writes the raw 2FA secret and
# password digest — into a table with a far wider audience than the secret.
#
# SECRET-HANDLING: every disclosure assertion is on the ABSENCE of a synthetic
# plaintext. `discloses?` returns a bare boolean and each failure carries an
# explicit message, so neither RSpec's differ nor a failure line can print
# secret material. Do not "improve" these by asserting on the hash itself.
#
# The redaction assertions are deliberately paired with SURVIVAL assertions: a
# mutant that redacts everything would destroy the audit trail while passing
# every absence check, so benign values are pinned too.
RSpec.describe "Auditable secret redaction" do
  # Namespaced rather than bare constants: a constant assigned inside an
  # RSpec block lands on Object, which is the duplicate-constant-clobber shape
  # that produces order-dependent flakes across this shared suite.
  module SyntheticAuditProbe
    API_KEY = "zz-synthetic-audit-probe-api-key"
    API_SECRET = "zz-synthetic-audit-probe-api-secret"
    ACCESS_TOKEN = "zz-synthetic-audit-probe-access-token"
    ROTATED_KEY = "zz-synthetic-audit-probe-rotated"
    TOTP_SECRET = "zz-synthetic-audit-probe-totp-secret"
    PASSWORD = "zz-synthetic-audit-probe-Pw1!"
    EMAIL = "zz-synthetic-audit-probe@example.invalid"
    BENIGN_NAME = "zz-synthetic-audit-probe-benign-name"

    FILTERED = Auditable::REDACTED_PLACEHOLDER
  end

  # Returns a bare boolean; never returns or raises with the value in it.
  def discloses?(values, secret)
    return false if values.blank?

    values.to_json.include?(secret)
  end

  def audit_rows_for(record)
    AuditLog.where(resource_type: record.class.name, resource_id: record.id)
  end

  # Asserts across BOTH value columns of every audit row for the record, so a
  # fix that only covers one callback cannot pass.
  def expect_no_disclosure(record, *secrets)
    rows = audit_rows_for(record).to_a
    expect(rows).not_to be_empty, "no audit row was written — the oracle would pass vacuously"

    rows.each do |row|
      secrets.each do |secret|
        expect(discloses?(row.old_values, secret)).to be(false),
          "audit_logs##{row.id} (#{row.action}) old_values disclosed a synthetic secret (value withheld)"
        expect(discloses?(row.new_values, secret)).to be(false),
          "audit_logs##{row.id} (#{row.action}) new_values disclosed a synthetic secret (value withheld)"
      end
    end
  end

  describe "Ai::DataSourceCredential" do
    it "does not write encrypted attribute plaintext on CREATE" do
      credential = nil

      Auditable.with_logging do
        credential = create(
          :ai_data_source_credential,
          encrypted_api_key: SyntheticAuditProbe::API_KEY,
          encrypted_api_secret: SyntheticAuditProbe::API_SECRET
        )
      end

      expect_no_disclosure(credential, SyntheticAuditProbe::API_KEY, SyntheticAuditProbe::API_SECRET)
    end

    it "does not write encrypted attribute plaintext on UPDATE" do
      credential = create(:ai_data_source_credential, encrypted_api_key: SyntheticAuditProbe::API_KEY)

      Auditable.with_logging do
        credential.update!(encrypted_access_token: SyntheticAuditProbe::ACCESS_TOKEN)
      end

      expect_no_disclosure(credential, SyntheticAuditProbe::API_KEY, SyntheticAuditProbe::ACCESS_TOKEN)
    end

    it "does not write encrypted attribute plaintext on DESTROY" do
      credential = create(:ai_data_source_credential, encrypted_api_key: SyntheticAuditProbe::API_KEY)

      Auditable.with_logging { credential.destroy! }

      expect_no_disclosure(credential, SyntheticAuditProbe::API_KEY)
    end

    # Anti-over-redaction oracle. Without this, a mutant that maps EVERY key to
    # the placeholder passes every absence assertion above while silently
    # destroying the audit trail.
    it "redacts the secret but preserves a benign attribute's real value on CREATE" do
      credential = nil

      Auditable.with_logging do
        credential = create(
          :ai_data_source_credential,
          name: SyntheticAuditProbe::BENIGN_NAME,
          encrypted_api_key: SyntheticAuditProbe::API_KEY
        )
      end

      row = audit_rows_for(credential).find_by(action: "created")
      expect(row.new_values["encrypted_api_key"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.new_values["name"]).to eq(SyntheticAuditProbe::BENIGN_NAME)
    end

    it "still records THAT a secret attribute changed, in BOTH value columns" do
      credential = create(:ai_data_source_credential, encrypted_api_key: SyntheticAuditProbe::API_KEY)

      Auditable.with_logging do
        credential.update!(
          encrypted_api_key: SyntheticAuditProbe::ROTATED_KEY,
          name: SyntheticAuditProbe::BENIGN_NAME
        )
      end

      row = audit_rows_for(credential).find_by(action: "updated")
      expect(row.old_values["encrypted_api_key"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.new_values["encrypted_api_key"]).to eq(SyntheticAuditProbe::FILTERED)
      # ...and a benign change in the same update keeps both real halves.
      expect(row.new_values["name"]).to eq(SyntheticAuditProbe::BENIGN_NAME)
    end
  end

  describe "User" do
    it "does not write the 2FA secret on UPDATE" do
      user = create(:user)

      Auditable.with_logging { user.update!(two_factor_secret: SyntheticAuditProbe::TOTP_SECRET) }

      expect_no_disclosure(user, SyntheticAuditProbe::TOTP_SECRET)
    end

    # The concern's own exclusion list named password_digest, but the update
    # callback never consulted that list, so the digest landed anyway.
    it "does not write password_digest on UPDATE" do
      user = create(:user)

      Auditable.with_logging { user.update!(password: SyntheticAuditProbe::PASSWORD) }

      digest = user.reload.password_digest
      expect(digest).to be_present
      expect_no_disclosure(user, digest)
    end

    # password_digest used to be DROPPED from the create path. It is now
    # redacted in place instead, so the key survives on every path. Pinned
    # because it is a deliberate behaviour change, not an accident.
    it "redacts rather than drops password_digest on CREATE" do
      user = nil

      Auditable.with_logging { user = create(:user, password: SyntheticAuditProbe::PASSWORD) }

      row = audit_rows_for(user).find_by(action: "created")
      expect(row.new_values).to have_key("password_digest")
      expect(row.new_values["password_digest"]).to eq(SyntheticAuditProbe::FILTERED)
      expect_no_disclosure(user, user.reload.password_digest)
    end

    it "does not write the encrypted email on CREATE" do
      user = nil

      Auditable.with_logging { user = create(:user, email: SyntheticAuditProbe::EMAIL) }

      expect_no_disclosure(user, SyntheticAuditProbe::EMAIL)
    end
  end
end
