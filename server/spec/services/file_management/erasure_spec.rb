# frozen_string_literal: true

require 'rails_helper'

# IMP-d97f6e3bbc2b — GDPR files erasure. The two defects the withdrawn
# implementation (IMP-bf52b4da135b) demonstrated by execution are pinned here
# as the two red oracles, each in the exact shape it was observed:
#
#   1. FK raise: a FileManagement::Object referenced by a chat attachment is
#      the target of a NO ACTION foreign key (fk_rails_ca093e583a on
#      chat_message_attachments), so a plain destroy raises
#      ActiveRecord::InvalidForeignKey.
#   2. Uncompensated share deletion: shares deleted for the whole scope up
#      front, then a raise mid-loop, left an UNRELATED file's shares gone with
#      its row still in place — destruction with no erasure.
#
# The erasure must therefore (a) route around the restrict FKs through the
# referent seam, (b) make every file's erasure atomic — a raise anywhere
# inside it leaves NO destruction behind, asserted as a rollback — and (c)
# refuse to count a file whose blob the provider did not remove.
RSpec.describe FileManagement::Erasure do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:storage) { create(:file_storage, account: account) }
  let(:provider) { instance_double(StorageProviders::LocalStorage) }

  before do
    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
    allow(StorageProviderFactory).to receive(:create).and_return(provider)
    allow(provider).to receive(:initialize_storage).and_return(true)
    allow(provider).to receive(:delete_file).and_return(true)
  end

  def personal_file(**attrs)
    create(:file_object, account: account, storage: storage, uploaded_by: user, **attrs)
  end

  def erase(scope = FileManagement::Object.where(account_id: account.id), **opts)
    described_class.call(scope: scope, **opts)
  end

  describe 'oracle 1 — the restrict FK' do
    let!(:file) { personal_file }
    let!(:attachment) do
      message = create(:chat_message)
      create(:chat_message_attachment, message: message, file_object: file)
    end

    it 'is the exact raise shape the naive destroy produces (characterisation, not the fix)' do
      expect { file.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_rails_ca093e583a/)
      expect(FileManagement::Object.exists?(file.id)).to be true
    end

    it 'erases a chat-attached file by releasing the attachment reference first' do
      result = erase

      expect(result.erased_count).to eq(1)
      expect(result.failures).to be_empty
      expect(FileManagement::Object.exists?(file.id)).to be false
      expect(attachment.reload.file_object_id).to be_nil
    end
  end

  describe 'oracle 2 — uncompensated share deletion' do
    let!(:good) { personal_file(filename: 'good.pdf') }
    let!(:bad)  { personal_file(filename: 'bad.pdf') }
    let!(:good_share) { create(:file_share, object: good, account: account, created_by: user) }
    let!(:bad_share)  { create(:file_share, object: bad, account: account, created_by: user) }

    before do
      # The real failure shape: every storage provider rescues internally and
      # RETURNS false; none of them raises.
      allow(provider).to receive(:delete_file) do |file_object|
        file_object.id != bad.id
      end
    end

    it 'rolls the failed file back whole — row AND shares survive — while the good file is erased' do
      result = erase

      expect(result.erased_count).to eq(1)
      expect(FileManagement::Object.exists?(good.id)).to be false
      expect(FileManagement::Share.exists?(good_share.id)).to be false

      expect(FileManagement::Object.exists?(bad.id)).to be true
      expect(FileManagement::Share.exists?(bad_share.id)).to be true
    end

    it 'does not count the file whose blob the provider did not remove, and names it' do
      result = erase

      expect(result.erased_count).to eq(1)
      expect(result.failures).to contain_exactly(
        hash_including(id: bad.id, kind: 'error', reason: 'storage_removal_failed')
      )
    end
  end

  describe 'rollback on a raise inside the per-file transaction' do
    let!(:file) { personal_file }
    let!(:share) { create(:file_share, object: file, account: account, created_by: user) }

    it 'leaves no destruction behind when a later referent release raises — the earlier release is rolled back' do
      # Registered AFTER the core chat handler, so by the time it raises the
      # attachment pointer has already been nullified inside the transaction;
      # the rollback is what restores it.
      message = create(:chat_message)
      attachment = create(:chat_message_attachment, message: message, file_object: file)
      FileManagement::ErasureReferentRegistry.register(:exploding) do |action, _payload|
        raise 'boom' if action == :release
        {}
      end

      result = erase

      expect(result.erased_count).to eq(0)
      expect(result.failures).to contain_exactly(hash_including(id: file.id, kind: 'error'))
      expect(FileManagement::Object.exists?(file.id)).to be true
      expect(FileManagement::Share.exists?(share.id)).to be true
      expect(attachment.reload.file_object_id).to eq(file.id)
    ensure
      FileManagement::ErasureReferentRegistry.unregister(:exploding)
    end

    it 'does not count, destroy twice, or fail a file a concurrent erasure already removed' do
      # The worker's retry middleware re-sends a timed-out DELETE while the
      # server may still be inside the first batch. The per-file row lock
      # serialises the two; the loser finds no row and reports nothing.
      FileManagement::ErasureReferentRegistry.register(:racing_erasure) do |action, payload|
        if action == :holds
          # Raw deletes, no callbacks: the other request's commit, as seen
          # from this one.
          FileManagement::Share.where(file_object_id: payload).delete_all
          FileManagement::ProcessingJob.where(file_object_id: payload).delete_all
          FileManagement::Object.where(id: payload).delete_all
        end
        {}
      end
      expect(provider).not_to receive(:delete_file)

      result = erase

      expect(result.erased_count).to eq(0)
      expect(result.failures).to be_empty
      expect(result.remaining).to eq(0)
    ensure
      FileManagement::ErasureReferentRegistry.unregister(:racing_erasure)
    end

    it 'refuses a malformed cursor instead of handing it to the database' do
      expect { erase(after_id: 'not-a-uuid') }.to raise_error(ArgumentError, /cursor/)
      expect(FileManagement::Object.exists?(file.id)).to be true
    end

    it 'treats an unregistered restrict FK as a hold, not a crash, and leaves the file intact' do
      # Simulate a referent nobody registered: the chat handler is removed so
      # the attachment's FK fires inside the transaction, where it is caught.
      message = create(:chat_message)
      create(:chat_message_attachment, message: message, file_object: file)
      chat_handler = FileManagement::ErasureReferentRegistry.handlers[:chat_message_attachments]
      FileManagement::ErasureReferentRegistry.unregister(:chat_message_attachments)

      result = erase

      expect(result.erased_count).to eq(0)
      expect(result.failures).to contain_exactly(
        hash_including(id: file.id, kind: 'held', reason: 'referenced_by_restrict_fk')
      )
      expect(FileManagement::Object.exists?(file.id)).to be true
      expect(FileManagement::Share.exists?(share.id)).to be true
    ensure
      FileManagement::ErasureReferentRegistry.register(:chat_message_attachments, chat_handler) if chat_handler
    end
  end

  describe 'the referent seam' do
    let!(:file) { personal_file }

    it 'refuses a file a registered handler holds, with the handler-authored reason, and never touches it' do
      FileManagement::ErasureReferentRegistry.register(:boot_images) do |action, payload|
        action == :holds ? payload.index_with { 'held_by_boot_image' } : nil
      end

      expect(provider).not_to receive(:delete_file)
      result = erase

      expect(result.erased_count).to eq(0)
      expect(result.failures).to contain_exactly(
        hash_including(id: file.id, kind: 'held', reason: 'held_by_boot_image')
      )
      expect(FileManagement::Object.exists?(file.id)).to be true
    ensure
      FileManagement::ErasureReferentRegistry.unregister(:boot_images)
    end

    it 'registers the core chat-attachment release handler at boot' do
      expect(FileManagement::ErasureReferentRegistry.registered?(:chat_message_attachments)).to be true
    end
  end

  describe 'category policy — only personal artifacts are erased' do
    it 'retains platform artifacts in the scope and reports them as retained, not erased' do
      personal = personal_file(category: 'user_upload')
      disk_image = personal_file(category: 'disk_image')
      attestation = personal_file(category: 'attestation_proof')

      result = erase

      expect(result.erased_count).to eq(1)
      expect(result.retained_count).to eq(2)
      expect(FileManagement::Object.exists?(personal.id)).to be false
      expect(FileManagement::Object.exists?(disk_image.id)).to be true
      expect(FileManagement::Object.exists?(attestation.id)).to be true
    end

    it 'includes soft-deleted personal files — the platform still holds them' do
      file = personal_file(deleted_at: 1.day.ago, deleted_by: user)

      expect(erase.erased_count).to eq(1)
      expect(FileManagement::Object.exists?(file.id)).to be false
    end
  end

  describe 'batching' do
    let!(:files) { Array.new(5) { |i| personal_file(filename: "f#{i}.pdf") } }

    it 'erases at most batch_size files per call and reports a cursor with the remainder' do
      first = erase(batch_size: 2)

      expect(first.erased_count).to eq(2)
      expect(first.remaining).to eq(3)
      expect(first.cursor).to eq(files.map(&:id).sort[1])

      second = erase(batch_size: 2, after_id: first.cursor)
      expect(second.erased_count).to eq(2)
      expect(second.remaining).to eq(1)

      third = erase(batch_size: 2, after_id: second.cursor)
      expect(third.erased_count).to eq(1)
      expect(third.remaining).to eq(0)
      expect(third.cursor).to eq(files.map(&:id).max)
      expect(FileManagement::Object.where(account_id: account.id)).to be_empty
    end

    it 'advances the cursor past a failed file so a caller can never loop on it' do
      allow(provider).to receive(:delete_file).and_return(false)

      result = erase(batch_size: 5)

      expect(result.erased_count).to eq(0)
      expect(result.failures.size).to eq(5)
      expect(result.remaining).to eq(0)
      expect(result.cursor).to eq(files.map(&:id).max)
    end

    it 'clamps the batch size to the maximum' do
      expect(described_class.batch_size_for(10_000)).to eq(described_class::MAX_BATCH_SIZE)
      expect(described_class.batch_size_for(nil)).to eq(described_class::DEFAULT_BATCH_SIZE)
      expect(described_class.batch_size_for(0)).to eq(described_class::DEFAULT_BATCH_SIZE)
    end
  end

  describe 'the audit row written by the destroy' do
    it 'does not archive the personal content fields it just erased' do
      file = personal_file(
        filename: 'passport-scan.pdf',
        metadata: { 'subject' => 'passport' },
        exif_data: { 'gps' => '52.5,13.4' }
      )

      # Auditable.logging_enabled defaults to false in the test env; the
      # destroy's own audit row is only written inside with_logging.
      Auditable.with_logging { erase }

      row = AuditLog.where(resource_type: 'FileManagement::Object', resource_id: file.id, action: 'deleted').last
      expect(row).to be_present
      old_values = row.old_values || {}
      expect(old_values['filename']).to eq(Auditable::REDACTED_PLACEHOLDER)
      expect(old_values['storage_key']).to eq(Auditable::REDACTED_PLACEHOLDER)
      expect(old_values['metadata']).to eq(Auditable::REDACTED_PLACEHOLDER)
      expect(old_values['exif_data']).to eq(Auditable::REDACTED_PLACEHOLDER)
    end

    it 'writes no audit row for the versions and processing jobs it removes — they would archive the content too' do
      file = personal_file(filename: 'passport-scan.pdf')
      version = create(:file_version, object: file, account: file.account, change_description: 'passport re-scan')
      job = file.processing_jobs.create!(account: file.account, job_type: 'metadata_extract', status: 'pending',
                                         job_parameters: { 'subject' => 'passport' })

      Auditable.with_logging { erase }

      expect(FileManagement::Version.exists?(version.id)).to be false
      expect(FileManagement::ProcessingJob.exists?(job.id)).to be false
      expect(
        AuditLog.where(resource_type: %w[FileManagement::Version FileManagement::ProcessingJob], action: 'deleted')
      ).to be_empty
    end
  end
end
