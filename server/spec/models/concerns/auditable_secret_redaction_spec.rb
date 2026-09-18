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
    KUBECONFIG = "zz-synthetic-audit-probe-kubeconfig-yaml"
    SERVER_TOKEN = "zz-synthetic-audit-probe-k3s-server-token"
    AGENT_TOKEN = "zz-synthetic-audit-probe-k3s-agent-token"
    ROTATED_AGENT_TOKEN = "zz-synthetic-audit-probe-k3s-agent-token-rotated"
    BENIGN_ENDPOINT = "https://zz-synthetic-audit-probe.example.invalid:6443"

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

  # TRIPWIRE for the second redaction source. Auditable filters non-encrypted
  # values through `self.class.filter_attributes`, which INHERITS from
  # ActiveRecord::Base.filter_attributes. That base list is empty here only
  # because the railtie initializer "active_record.set_filter_attributes"
  # (activerecord/lib/active_record/railtie.rb) merges
  # config.filter_parameters on the :active_record load hook, and this app's
  # AR::Base is already loaded by then — config.filter_parameters carries ~50
  # entries (:token, :_key, :secret, :email, :crypt, :salt, :certificate ...)
  # that never arrive. If that load order is ever repaired, every Auditable
  # model would begin masking audit values on those substrings platform-wide,
  # gutting the trail. This example goes red first; the fix then is to narrow
  # audit_attribute_filter to each class's OWN declaration, not to relax it.
  it "keeps the global filter list out of the per-model redaction source" do
    expect(ActiveRecord::Base.filter_attributes).to eq([])
    expect(Rails.application.config.filter_parameters).not_to be_empty
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

    # IMP-01a07dd5. The offer named THREE columns as leaking; measured on HEAD,
    # only this one did. password_digest has been in ALWAYS_REDACTED_ATTRIBUTES
    # since the original fix (the two examples above pin it), so the offer was
    # wrong about it — and authorized_keys is a deliberate NON-fix, see below.
    #
    # reset_token_digest is the bcrypt digest of a password-RESET token, which
    # is the same class of material as password_digest sitting one line away in
    # the same model, redacted. It carries no `encrypts`, so
    # audit_redacted_attribute_names cannot see it. A digest is not directly
    # replayable, but a reset token has far less entropy than a password, which
    # makes an offline attack on its digest correspondingly cheaper — and the
    # inconsistency with password_digest is not defensible either way.
    it "does not write reset_token_digest on UPDATE" do
      user = create(:user)

      Auditable.with_logging do
        user.update!(reset_token_digest: BCrypt::Password.create(SyntheticAuditProbe::PASSWORD))
      end

      digest = user.reload.reset_token_digest
      expect(digest).to be_present
      expect_no_disclosure(user, digest)
    end

    it "keeps the key so the trail still records that a reset token was set" do
      user = create(:user)

      Auditable.with_logging do
        user.update!(reset_token_digest: BCrypt::Password.create(SyntheticAuditProbe::PASSWORD))
      end

      row = audit_rows_for(user).where(action: "updated").order(:created_at).last
      expect(row.new_values).to have_key("reset_token_digest")
      expect(row.new_values["reset_token_digest"]).to eq(SyntheticAuditProbe::FILTERED)
    end

    # A DELIBERATE NON-FIX, pinned so nobody "completes" the offer later.
    #
    # The same offer asked for authorized_keys to be redacted too. It must NOT
    # be. These are OpenSSH PUBLIC keys — #authorized_keys_format rejects
    # anything that is not a valid authorized_keys line, so a private key cannot
    # land here — and they are published to every node in the account by design.
    # There is no secret to disclose.
    #
    # What there IS, is audit value: adding a key to this column grants SSH
    # access to the whole fleet, and "operator X added ssh-ed25519 AAAA..." is
    # precisely the event an audit trail exists to capture. Redacting it would
    # replace the record of a privileged change with [FILTERED] and make the
    # trail WORSE while looking like a security improvement.
    it "still records authorized_keys in full — a public key is not a secret" do
      user = create(:user)
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuditProbePublicKeyValue probe@example.com"

      Auditable.with_logging { user.update!(authorized_keys: key) }

      row = audit_rows_for(user).where(action: "updated").order(:created_at).last
      expect(row.new_values["authorized_keys"].to_s).to include("AAAAC3NzaC1lZDI1NTE5")
      expect(row.new_values["authorized_keys"].to_s).not_to eq(SyntheticAuditProbe::FILTERED)
    end

    it "does not write the encrypted email on CREATE" do
      user = nil

      Auditable.with_logging { user = create(:user, email: SyntheticAuditProbe::EMAIL) }

      expect_no_disclosure(user, SyntheticAuditProbe::EMAIL)
    end

    # DELIBERATE COLLATERAL, pinned so the next reader sees a decision rather
    # than a regression. `filter_attributes` matches attribute names as
    # case-insensitive SUBSTRINGS, so User's `encrypts :email` entry also
    # covers email_verification_sent_at / email_verification_token /
    # email_verification_token_expires_at / email_verified / email_verified_at,
    # and `encrypts :backup_codes` covers two_factor_backup_codes_generated_at.
    # Those six are the ONLY columns anywhere that honouring the list newly
    # masks (measured across every Auditable model), they are timestamps and
    # flags rather than evidence, User#inspect already masks them, and no
    # consumer reads them out of an audit row. Narrow the list, not this seam,
    # if one ever needs to survive.
    it "also masks the verification columns that User's email filter matches by substring" do
      user = nil

      Auditable.with_logging { user = create(:user, email: SyntheticAuditProbe::EMAIL) }

      row = audit_rows_for(user).find_by(action: "created")
      expect(row.new_values).to have_key("email_verified")
      expect(row.new_values["email_verified"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.new_values["email_verification_token"]).to eq(SyntheticAuditProbe::FILTERED)
      # ...while a benign, non-matching column keeps its real value.
      expect(row.new_values["status"]).to eq(user.status)
    end
  end

  # The encrypted_* columns here are NOT `encrypts` attributes: the cluster
  # stores the cluster-admin kubeconfig and both k3s node-join tokens as
  # plaintext under an encrypted_ name. The `encrypts`-derived redaction set is
  # therefore empty for this model, and the only thing keeping the credentials
  # out of audit_logs is the model's own `filter_attributes` declaration — the
  # list `inspect` already masks with — which Auditable must honour.
  #
  # DESTROY is the case that matters most: decommissioning a cluster hard-deletes
  # the row, so the audit snapshot is the copy that outlives the cluster.
  describe "Devops::KubernetesCluster" do
    def build_cluster_with_credentials(**overrides)
      create(
        :devops_kubernetes_cluster,
        encrypted_kubeconfig: SyntheticAuditProbe::KUBECONFIG,
        encrypted_server_token: SyntheticAuditProbe::SERVER_TOKEN,
        encrypted_agent_token: SyntheticAuditProbe::AGENT_TOKEN,
        **overrides
      )
    end

    def all_cluster_secrets
      [
        SyntheticAuditProbe::KUBECONFIG,
        SyntheticAuditProbe::SERVER_TOKEN,
        SyntheticAuditProbe::AGENT_TOKEN
      ]
    end

    it "declares the plaintext credential columns as filtered attributes" do
      declared = Devops::KubernetesCluster.filter_attributes.map(&:to_s)

      expect(declared).to include("encrypted_kubeconfig", "encrypted_server_token", "encrypted_agent_token")
    end

    it "does not write the kubeconfig or node-join tokens on DESTROY" do
      cluster = build_cluster_with_credentials

      Auditable.with_logging { cluster.destroy! }

      expect(Devops::KubernetesCluster.exists?(cluster.id)).to be(false)
      expect_no_disclosure(cluster, *all_cluster_secrets)
    end

    it "does not write the kubeconfig or node-join tokens on CREATE" do
      cluster = nil

      Auditable.with_logging { cluster = build_cluster_with_credentials }

      expect_no_disclosure(cluster, *all_cluster_secrets)
    end

    it "does not write either half of a rotated node-join token on UPDATE" do
      cluster = build_cluster_with_credentials

      Auditable.with_logging do
        cluster.update!(encrypted_agent_token: SyntheticAuditProbe::ROTATED_AGENT_TOKEN)
      end

      expect_no_disclosure(cluster, SyntheticAuditProbe::AGENT_TOKEN, SyntheticAuditProbe::ROTATED_AGENT_TOKEN)
    end

    # Anti-over-redaction oracle for the filter_attributes path: the credential
    # keys survive as placeholders (so the trail still shows the cluster HAD a
    # kubeconfig) while benign columns — including encryption_key_id, which
    # merely names a key — keep their real values.
    it "redacts the credential columns in place but preserves benign attributes on DESTROY" do
      key_id = SecureRandom.uuid
      cluster = build_cluster_with_credentials(
        name: SyntheticAuditProbe::BENIGN_NAME,
        api_endpoint: SyntheticAuditProbe::BENIGN_ENDPOINT,
        encryption_key_id: key_id
      )

      Auditable.with_logging { cluster.destroy! }

      row = audit_rows_for(cluster).find_by(action: "deleted")
      expect(row).to be_present
      expect(row.old_values["encrypted_kubeconfig"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.old_values["encrypted_server_token"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.old_values["encrypted_agent_token"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.old_values["name"]).to eq(SyntheticAuditProbe::BENIGN_NAME)
      expect(row.old_values["api_endpoint"]).to eq(SyntheticAuditProbe::BENIGN_ENDPOINT)
      expect(row.old_values["encryption_key_id"]).to eq(key_id)
    end

    # The same declaration is what keeps the credentials out of console and
    # log output, so pin that side too rather than let the two drift.
    it "masks the credential columns in #inspect" do
      cluster = build_cluster_with_credentials

      all_cluster_secrets.each do |secret|
        expect(cluster.inspect.include?(secret)).to be(false), "#inspect disclosed a synthetic secret (value withheld)"
      end
    end
  end

  # Auditable#audit_extra_redactions (IMP-7ff4be3454a6): a per-INSTANCE,
  # per-WRITE redaction extension, deliberately generic — nothing here is
  # User- or GDPR-specific, unlike the class-wide `filter_attributes` seam
  # exercised everywhere else in this file. `status` is used purely as an
  # arbitrary, ordinarily-unredacted User attribute to prove the MECHANISM;
  # it carries no significance of its own to these examples.
  describe "Auditable#audit_extra_redactions" do
    it "redacts only the named field(s) on the write it was set for" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]
        user.update!(status: "inactive", failed_login_attempts: 3)
      end

      row = audit_rows_for(user).where(action: "updated").order(:created_at).last
      expect(row.old_values["status"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(row.new_values["status"]).to eq(SyntheticAuditProbe::FILTERED)
      # Anti-over-redaction oracle: a field NOT listed in
      # audit_extra_redactions keeps its real value — this is a targeted
      # redaction, not a blanket suppression of the whole row.
      expect(row.new_values["failed_login_attempts"]).to eq(3)
    end

    it "clears itself after the write, so a later update of the same instance audits normally" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]
        user.update!(status: "inactive")

        user.update!(status: "suspended")
      end

      rows = audit_rows_for(user).where(action: "updated").order(:created_at).to_a
      expect(rows.length).to eq(2)
      expect(rows.first.new_values["status"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(rows.second.new_values["status"]).to eq("suspended")
    end

    it "does not affect a different record of the same class that never set it" do
      redacted_user = create(:user)
      plain_user = create(:user)

      Auditable.with_logging do
        redacted_user.audit_extra_redactions = %w[status]
        redacted_user.update!(status: "inactive")
        plain_user.update!(status: "inactive")
      end

      redacted_row = audit_rows_for(redacted_user).where(action: "updated").order(:created_at).last
      plain_row = audit_rows_for(plain_user).where(action: "updated").order(:created_at).last

      expect(redacted_row.new_values["status"]).to eq(SyntheticAuditProbe::FILTERED)
      expect(plain_row.new_values["status"]).to eq("inactive")
    end

    # The four examples below each pin one of the FOUR clear sites the
    # declaration on audit_extra_redactions documents. Every save shape here
    # was verified directly (not assumed) against this Rails version before
    # being pinned — see that comment for what each one measured.
    it "clears itself on a genuine no-op save (no attribute actually changed), so a later real update audits normally" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]
        user.update!(status: user.status) # same value: saved_changes ends up {}

        user.update!(status: "inactive")
      end

      rows = audit_rows_for(user).where(action: "updated").order(:created_at).to_a
      expect(rows.length).to eq(1) # the no-op save wrote no "updated" audit row at all
      expect(rows.first.new_values["status"]).to eq("inactive")
    end

    it "clears itself when only timestamp columns changed, so a later real update audits normally" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]
        # #touch does not run after_update in this Rails version (measured),
        # so it cannot exercise this branch; an explicit updated_at-only
        # #update! does reach log_record_update with saved_changes ==
        # {"updated_at" => [...]}, which is empty after the
        # .except("updated_at", "created_at") filter.
        user.update!(updated_at: Time.current + 1)

        user.update!(status: "inactive")
      end

      rows = audit_rows_for(user).where(action: "updated").order(:created_at).to_a
      expect(rows.length).to eq(1)
      expect(rows.first.new_values["status"]).to eq("inactive")
    end

    it "clears itself when a save fails validation, so a later successful update audits normally" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]
        expect { user.update!(email: "") }.to raise_error(ActiveRecord::RecordInvalid)

        # Discards the invalid in-memory email so the NEXT update can
        # succeed; reload never touches audit_extra_redactions (not a
        # DB-backed column), so if this example passes, the clear is
        # attributable to after_validation, not to this reload.
        user.reload
        user.update!(status: "inactive")
      end

      rows = audit_rows_for(user).where(action: "updated").order(:created_at).to_a
      expect(rows.length).to eq(1)
      expect(rows.first.new_values["status"]).to eq("inactive")
    end

    it "clears itself when a successful update is rolled back by an enclosing transaction, so a later update audits normally" do
      user = create(:user)

      Auditable.with_logging do
        user.audit_extra_redactions = %w[status]

        ActiveRecord::Base.transaction do
          user.update!(status: "inactive")
          raise ActiveRecord::Rollback
        end
        expect(user.reload.status).to eq("active") # confirms the rollback actually happened

        user.update!(status: "suspended")
      end

      rows = audit_rows_for(user).where(action: "updated").order(:created_at).to_a
      expect(rows.length).to eq(1) # the rolled-back update's audit row never committed either
      expect(rows.first.new_values["status"]).to eq("suspended")
    end
  end
end
