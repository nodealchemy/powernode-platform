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
      expect(meta).to include("account_id" => account_id, "actor_id" => actor.id)
      expect(meta["name_digest"]).to eq(Digest::SHA256.hexdigest("Doomed Account"))
      expect(meta.to_json).not_to include("Doomed Account")
      expect(meta["counts"]).to include("table" => "api_keys", "rows" => 1)
      expect(meta["revoked_records"]).to eq([ { "model" => "ApiKey", "ids" => [ key.id ] } ])
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
