# frozen_string_literal: true

require "rails_helper"

# Account#destroy! must not erase its own audit trail (review #2) and must not leave
# secret-store orphans behind silently (review #3).
RSpec.describe "Account teardown audit trail" do
  let(:account) { create(:account, name: "Doomed Account") }
  let(:actor) { create(:user, account: create(:account)) }

  def platform_rows(action) = AuditLog.where(account_id: nil, action: action)

  describe "platform-scoped audit survives the account" do
    let!(:key) { create(:api_key, account: account) }
    let!(:old_row) do
      AuditLog.log_action(action: "api_key_created", resource: key, account: account, user: nil,
                          metadata: { "note" => "first key" })
    end

    before do
      create(:user, account: account)
      account.teardown_actor = actor
    end

    it "re-homes key-operation audit rows, records each destroyed key, and writes one account.destroyed row" do
      account_id = account.id
      account.destroy!

      expect(AuditLog.where(account_id: account_id)).to be_empty

      retained = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == old_row.id }
      expect(retained).to be_present
      expect(retained.metadata).to include("original_action" => "api_key_created", "original_account_id" => account_id)

      revoked = platform_rows("account.teardown_key_revoked").find_by(resource_id: key.id)
      expect(revoked.resource_type).to eq("ApiKey")

      destroyed = platform_rows("account.destroyed")
      expect(destroyed.count).to eq(1)
      meta = destroyed.first.metadata
      expect(meta).to include("account_id" => account_id, "actor_id" => actor.id, "actor_label" => "user:#{actor.id}")
      expect(meta["name_digest"]).to eq(Digest::SHA256.hexdigest("Doomed Account"))
      expect(meta.to_json).not_to include("Doomed Account")
      expect(meta["counts"]).to include("table" => "api_keys", "rows" => 1)
      expect(meta["revoked_records"]).to eq([ { "model" => "ApiKey", "ids" => [ key.id ] } ])
    end

    it "carries the original hash chain position on each copy and records the deleted sequence range" do
      account_id = account.id
      originals = AuditLog.where(account_id: account_id).order(:sequence_number).to_a
      expect(originals.map(&:sequence_number).compact).not_to be_empty
      account.destroy!

      copy = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == old_row.id }
      expect(copy.metadata).to include(
        "original_integrity_hash" => old_row.integrity_hash,
        "original_previous_hash" => old_row.previous_hash,
        "original_sequence_number" => old_row.sequence_number
      )
      range = platform_rows("account.destroyed").first.metadata["deleted_sequence_range"]
      seqs = originals.map(&:sequence_number).compact
      expect(range).to include("min" => seqs.min, "max" => seqs.max)
      expect(range["count"]).to be >= originals.size
    end

    it "scrubs sensitive keys out of the copied metadata, nested too" do
      key.update_columns(updated_at: Time.current)
      row = AuditLog.new(action: "api_key_revoked", resource_type: "ApiKey", resource_id: key.id, account: account,
                         source: "system", metadata: { "ok" => "kept", "old_key_preview" => "abcd1234",
                                                         "nested" => { "client_secret_hint" => "zz", "fine" => 1 } })
      row.save!(validate: false) # bypass the model's own redactor: this proves the teardown scrubs independently
      row.update_columns(metadata: { "ok" => "kept", "old_key_preview" => "abcd1234",
                                     "nested" => { "client_secret_hint" => "zz", "fine" => 1 } })
      account.destroy!

      copy = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == row.id }
      meta = copy.metadata["original_metadata"]
      expect(meta).to include("ok" => "kept")
      expect(meta.to_json).not_to include("abcd1234")
      expect(meta.to_json).not_to include("zz")
      expect(meta["nested"]).to include("fine" => 1)
    end

    # Written the way api_keys_controller#log_api_key_action writes: ip, user agent and metadata.
    def write_like_controller(action, extra_metadata = {})
      AuditLog.create!(action: action, resource_type: "ApiKey", resource_id: key.id, account: account, user: @author,
                       source: "admin_panel", ip_address: "203.0.113.9", user_agent: "probe/1.0",
                       metadata: { "api_key_name" => key.name, "scopes" => [ "read" ] }.merge(extra_metadata))
    end

    def recompute(m)
      rebuilt = AuditLog.new(action: m["original_action"], resource_type: m["original_resource_type"],
                             resource_id: m["original_resource_id"], user_id: m["original_user_id"],
                             account_id: m["original_account_id"], metadata: m["original_metadata"],
                             sequence_number: m["original_sequence_number"],
                             ip_address: m["original_ip_address"], user_agent: m["original_user_agent"])
      rebuilt.id = m["original_id"]
      rebuilt.created_at = Time.zone.parse(m["original_created_at"])
      Audit::LogIntegrityService.calculate_hash(rebuilt, previous_hash: m["original_previous_hash"])
    end

    it "keeps the author, ip and user agent, so an unscrubbed controller-written row's hash recomputes" do
      @author = create(:user, account: account)
      row = write_like_controller("api_key_regenerated")
      expect(row.user_id).to eq(@author.id)

      account.destroy!

      m = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == row.id }.metadata
      expect(m).to include("original_user_id" => @author.id, "original_user_id_restored" => true,
                           "original_ip_address" => "203.0.113.9", "original_user_agent" => "probe/1.0",
                           "original_metadata_scrubbed" => false)
      expect(recompute(m)).to eq(m["original_integrity_hash"])
    end

    it "flags a scrubbed copy: its hash is then an attestation, not a recomputable value" do
      @author = create(:user, account: account)
      row = write_like_controller("api_key_regenerated", "old_key_preview" => "sk-ab...cd")

      account.destroy!

      m = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == row.id }.metadata
      expect(m["original_metadata_scrubbed"]).to be(true)
      expect(m["original_metadata"].to_json).not_to include("sk-ab")
      expect(recompute(m)).not_to eq(m["original_integrity_hash"])
    end

    it "destroys an account whose audit_logs association was already loaded (no stale-restrict error)" do
      create(:user, account: account)
      account.audit_logs.load
      expect(account.audit_logs.target).not_to be_empty

      expect { account.destroy! }.not_to raise_error
      expect(Account.exists?(account.id)).to be false
    end

    it "keeps identifiers and public material in the copied metadata while masking secret-looking keys" do
      row = AuditLog.log_action(action: "api_key_revoked", resource: key, account: account, metadata: {
        "key_id" => "kid-1", "key_ids" => [ "a" ], "public_key" => "PUBLIC", "key_fingerprint" => "ab:cd", "key_name" => "ci",
        "old_key_preview" => "abcd1234", "client_secret" => "shh"
      })
      row.update_columns(metadata: row.metadata.merge("old_key_preview" => "abcd1234", "client_secret" => "shh"))
      account.destroy!

      copy = platform_rows("account.teardown_key_audit_retained").find { |r| r.metadata["original_id"] == row.id }
      meta = copy.metadata["original_metadata"]
      expect(meta).to include("key_id" => "kid-1", "key_ids" => [ "a" ], "public_key" => "PUBLIC",
                              "key_fingerprint" => "ab:cd", "key_name" => "ci")
      expect(meta.to_json).not_to include("abcd1234")
      expect(meta.to_json).not_to include("shh")
    end

    it "does not retain a look-alike action that is not on the key-operation list" do
      lookalike = AuditLog.log_action(action: "user_created", resource: key, account: account, metadata: { "note" => "x" })
      account.destroy!
      expect(platform_rows("account.teardown_key_audit_retained").map { |r| r.metadata["original_id"] }).not_to include(lookalike.id)
    end

    it "attributes the deletion to an explicit actor, or to the OS process when none is given" do
      account.teardown_actor = nil
      account.destroy!
      meta = platform_rows("account.destroyed").first.metadata
      expect(meta["actor_id"]).to be_nil
      expect(meta["actor_label"]).to match(/\Aunattributed:process:.+@.+\z/)
    end

    it "chains the platform rows into the global audit chain" do
      account.destroy!
      row = platform_rows("account.destroyed").first
      expect(row).to have_attributes(sequence_number: be_present, previous_hash: be_present, integrity_hash: be_present)
    end

    it "fails closed: an audit failure aborts the teardown and deletes nothing" do
      allow(AuditLog).to receive(:create!).and_wrap_original do |orig, attrs = {}, &blk|
        raise ActiveRecord::StatementInvalid, "audit store down" if attrs[:action] == "account.destroyed"

        orig.call(attrs, &blk)
      end

      expect { account.destroy! }.to raise_error(ActiveRecord::StatementInvalid)

      expect(Account.exists?(account.id)).to be true
      expect(ApiKey.exists?(key.id)).to be true
      expect(AuditLog.exists?(old_row.id)).to be true
    end
  end

  describe "tenant scopes never include platform (NULL-account) rows" do
    it "excludes them from account.audit_logs and AuditLog.by_account (the API listing is covered in audit_logs_spec)" do
      survivor = AuditLog.create!(action: "account.destroyed", resource_type: "Account", resource_id: SecureRandom.uuid,
                                  account: nil, source: "system", metadata: { "account_id" => SecureRandom.uuid })
      mine = AuditLog.log_action(action: "api_key_created", resource: create(:api_key, account: account), account: account)

      expect(account.audit_logs.pluck(:id)).to include(mine.id)
      expect(account.audit_logs.pluck(:id)).not_to include(survivor.id)
      expect(AuditLog.by_account(account).pluck(:id)).not_to include(survivor.id)
      expect(AuditLog.where(account_id: nil).pluck(:id)).to eq([ survivor.id ])
    end
  end

  describe "database and association guards on NULL-account rows" do
    it "has a CHECK constraint refusing a NULL account_id on an ordinary action, even past validations" do
      expect do
        AuditLog.insert_all!([ { action: "api_key_created", resource_type: "ApiKey", resource_id: "x", source: "system",
                                 severity: "low", risk_level: "low", account_id: nil } ])
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_audit_logs_account_unless_platform/)
    end

    it "allows a NULL account_id for the platform-scoped teardown actions" do
      expect do
        AuditLog.insert_all!([ { action: "account.destroyed", resource_type: "Account", resource_id: "x", source: "system",
                                 severity: "low", risk_level: "low", account_id: nil } ])
      end.not_to raise_error
    end

    it "keeps the constraint's action list in step with PLATFORM_SCOPED_ACTIONS" do
      definition = ActiveRecord::Base.connection.select_value(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'chk_audit_logs_account_unless_platform'"
      )
      AuditActions::PLATFORM_SCOPED_ACTIONS.each { |a| expect(definition).to include(a) }
    end

    it "restricts destroying an account through its audit_logs association" do
      expect(Account.reflect_on_association(:audit_logs).options[:dependent]).to eq(:restrict_with_exception)
    end
  end

  describe "platform audit rows do not need an account" do
    it "rejects an account-less row for an ordinary action" do
      row = AuditLog.new(action: "api_key_created", resource_type: "ApiKey", resource_id: SecureRandom.uuid,
                         source: "system", account: nil)
      expect(row).not_to be_valid
    end
  end

  describe "Vault pre-flight (review #3)" do
    it "refuses the teardown when Vault is the secret backend and is not healthy" do
      allow(Security::SecretStore).to receive(:backend).and_return(:vault)
      allow(Security::VaultClient).to receive(:instance).and_return(instance_double(Security::VaultClient, healthy?: false))

      expect(account.destroy).to be false
      expect(account.errors[:base].join).to match(/vault.*not healthy/i)
      expect(Account.exists?(account.id)).to be true
    end

    it "does not consult Vault for the database backend" do
      allow(Security::SecretStore).to receive(:backend).and_return(:database)
      expect(Security::VaultClient).not_to receive(:instance)
      expect { account.destroy! }.not_to raise_error
    end
  end

  describe "after-commit secret purge failure (review #3)" do
    it "leaves a durable retry task, with the error class only" do
      allow(Security::SecretStore).to receive(:purge_account).and_raise(Security::SecretStore::BackendUnavailable, "token s3cr3t")
      account_id = account.id

      expect { account.destroy! }.to change { PlatformPurgeTask.where(subject_id: account_id).count }.by(1)

      task = PlatformPurgeTask.find_by(subject_id: account_id)
      expect(task).to have_attributes(kind: "secret_store_account", status: "pending", last_error_class: "Security::SecretStore::BackendUnavailable")
      expect(task.attributes.values.join).not_to include("s3cr3t")
    end

    it "leaves no task when the purge succeeds" do
      allow(Security::SecretStore).to receive(:purge_account).and_return(0)
      expect { account.destroy! }.not_to change(PlatformPurgeTask, :count)
    end

    it "retries due tasks and completes them" do
      task = PlatformPurgeTask.enqueue!(kind: "secret_store_account", subject_id: SecureRandom.uuid, error: StandardError.new("x"))
      task.update_columns(next_attempt_at: 1.minute.ago)
      allow(Security::SecretStore).to receive(:purge_account).and_return(3)

      result = PlatformPurgeTask.run_due!

      expect(result).to include(completed: 1, failed: 0)
      expect(task.reload).to have_attributes(status: "completed", attempts: 2)
    end

    it "keeps a task pending with backoff when the retry fails again" do
      task = PlatformPurgeTask.enqueue!(kind: "secret_store_account", subject_id: SecureRandom.uuid, error: StandardError.new("x"))
      task.update_columns(next_attempt_at: 1.minute.ago)
      allow(Security::SecretStore).to receive(:purge_account).and_raise(Security::SecretStore::BackendUnavailable)

      PlatformPurgeTask.run_due!

      task.reload
      expect(task.status).to eq("pending")
      expect(task.next_attempt_at).to be > Time.current
      expect(task.attempts).to eq(2)
    end
  end
end
