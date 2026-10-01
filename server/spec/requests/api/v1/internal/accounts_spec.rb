# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Accounts', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  # owner is simply a user belonging to this account
  before do
    owner # ensure the owner user is created
  end

  describe 'GET /api/v1/internal/accounts/:id' do
    context 'with internal authentication' do
      it 'returns account details' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['account']).to include(
          'id' => account.id,
          'name' => account.name
        )
      end

      it 'includes owner information' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['account']).to have_key('owner_email')
      end

      it 'includes subscription status' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['account']).to have_key('status')
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/accounts/nonexistent-id', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/accounts/#{account.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/users' do
    before do
      create_list(:user, 3, account: account)
    end

    context 'with internal authentication' do
      it 'returns account users' do
        get "/api/v1/internal/accounts/#{account.id}/users", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(4) # 3 + owner
      end

      it 'includes user details' do
        get "/api/v1/internal/accounts/#{account.id}/users", headers: internal_headers, as: :json

        data = json_response_data
        first_user = data.first

        expect(first_user).to include('id', 'email', 'name')
      end
    end
  end

  # IMP-b33a3ecca331 (Fork 1): the worker's PATCH accounts/:id status:
  # 'terminated' call had no route at all, and 'terminated' was never a value
  # `valid_account_status` allowed. Operator decision: a narrow member action
  # that sets the existing 'cancelled' enum value — not a generic update.
  describe 'PATCH /api/v1/internal/accounts/:account_id/terminate' do
    context 'with internal authentication' do
      it 'sets the account status to cancelled' do
        patch "/api/v1/internal/accounts/#{account.id}/terminate", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['status']).to eq('cancelled')

        account.reload
        expect(account.status).to eq('cancelled')
      end

      it 'writes an account.terminate audit row' do
        patch "/api/v1/internal/accounts/#{account.id}/terminate", headers: internal_headers, as: :json

        expect_success_response
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.terminate')
        ).to be true
      end

      it 'is idempotent: succeeds without a duplicate audit row on an already-cancelled account' do
        account.update!(status: 'cancelled')

        expect {
          patch "/api/v1/internal/accounts/#{account.id}/terminate", headers: internal_headers, as: :json
        }.not_to change { AuditLog.where(account_id: account.id, action: 'account.terminate').count }

        expect_success_response
        account.reload
        expect(account.status).to eq('cancelled')
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/accounts/nonexistent-id/terminate', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/accounts/#{account.id}/terminate", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/accounts/:account_id/anonymize_audit_logs' do
    before do
      create_list(:audit_log, 5, account: account, user: owner, ip_address: '192.168.1.1')
    end

    context 'with internal authentication' do
      it 'anonymizes audit logs' do
        patch "/api/v1/internal/accounts/#{account.id}/anonymize_audit_logs", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Anonymized')

        # Verify audit logs are anonymized
        account.reload
        audit_log = AuditLog.where(account_id: account.id).first
        expect(audit_log.ip_address).to eq('0.0.0.0')
      end

      it 'writes an audit_logs row for the anonymize_audit_logs action itself' do
        # IMP-26a95cba1d43: log_internal_audit("account.anonymize_audit_logs", ...)
        # was never registered in AuditActions, so AuditLog.create! raised
        # ActiveRecord::RecordInvalid and the rescue in log_internal_audit
        # silently dropped the row — the endpoint above returned 200 while
        # writing no audit trail for its own effect. Assert the row EXISTS
        # with the exact action, not just that the request succeeded.
        patch "/api/v1/internal/accounts/#{account.id}/anonymize_audit_logs", headers: internal_headers, as: :json

        expect_success_response
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.anonymize_audit_logs')
        ).to be true
      end
    end
  end

  describe 'PATCH /api/v1/internal/accounts/:account_id/anonymize_payments' do
    before do
      skip 'Business billing module not loaded' unless defined?(Billing::Payment)
      create_list(:payment, 3, account: account)
    end

    context 'with internal authentication' do
      it 'anonymizes payment records' do
        patch "/api/v1/internal/accounts/#{account.id}/anonymize_payments", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Anonymized')
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.anonymize_payments')
        ).to be true
      end
    end
  end

  # IMP-d97f6e3bbc2b — the account-termination files path. IMP-bf52b4da135b
  # withdrew `files` because this action had never erased one (it was gated on
  # an association Account does not have) and a real erasure was blocked on
  # restrict FKs, a swallowed blob-removal failure and platform artifacts
  # sharing the scope. FileManagement::Erasure now resolves all three; this
  # action is one bounded batch of it, and the worker loops on the cursor.
  describe 'DELETE /api/v1/internal/accounts/:account_id/files' do
    let(:storage) { create(:file_storage, account: account) }
    let(:provider) { instance_double(StorageProviders::LocalStorage, delete_file: true, initialize_storage: true) }

    before do
      allow(StorageProviderFactory).to receive(:create).and_return(provider)
    end

    context 'with internal authentication' do
      it 'erases every personal file in the account, whoever uploaded it, and reports the count' do
        member = create(:user, account: account)
        mine = create(:file_object, account: account, storage: storage, uploaded_by: owner)
        theirs = create(:file_object, account: account, storage: storage, uploaded_by: member)

        delete "/api/v1/internal/accounts/#{account.id}/files", headers: internal_headers, as: :json

        expect_success_response
        expect(json_response_data['count']).to eq(2)
        expect(json_response_data['erased']).to be true
        expect(json_response_data['failed']).to eq([])
        expect(json_response_data['remaining']).to eq(0)
        expect(FileManagement::Object.exists?(mine.id)).to be false
        expect(FileManagement::Object.exists?(theirs.id)).to be false
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.delete_files')
        ).to be true
      end

      it 'does not destroy a disk image or an attestation proof — a termination is not a licence to erase platform artifacts' do
        disk_image = create(:file_object, account: account, storage: storage, uploaded_by: owner, category: 'disk_image')
        proof = create(:file_object, account: account, storage: storage, uploaded_by: owner, category: 'attestation_proof')

        delete "/api/v1/internal/accounts/#{account.id}/files", headers: internal_headers, as: :json

        expect_success_response
        expect(json_response_data['count']).to eq(0)
        expect(json_response_data['retained_platform_artifacts']).to eq(2)
        expect(FileManagement::Object.exists?(disk_image.id)).to be true
        expect(FileManagement::Object.exists?(proof.id)).to be true
      end

      it 'does not reach files in another account' do
        other = create(:file_object)

        delete "/api/v1/internal/accounts/#{account.id}/files", headers: internal_headers, as: :json

        expect(FileManagement::Object.exists?(other.id)).to be true
      end

      it 'reports a file whose blob delete failed as failed, not erased, and does not fail the request' do
        file = create(:file_object, account: account, storage: storage, uploaded_by: owner)
        allow(provider).to receive(:delete_file).and_return(false)

        delete "/api/v1/internal/accounts/#{account.id}/files", headers: internal_headers, as: :json

        # Not a 5xx: BackendApiClient raises on any non-2xx, which would abort
        # the whole termination; the worker reads `failed` and decides.
        expect(response).to have_http_status(:success)
        expect(json_response_data['count']).to eq(0)
        expect(json_response_data['failed']).to contain_exactly(
          hash_including('id' => file.id, 'kind' => 'error', 'reason' => 'storage_removal_failed')
        )
        expect(FileManagement::Object.exists?(file.id)).to be true
      end

      it 'honours batch_size and after_id so the worker can page through a large account' do
        files = create_list(:file_object, 3, account: account, storage: storage, uploaded_by: owner)

        delete "/api/v1/internal/accounts/#{account.id}/files",
               params: { batch_size: 2 }, headers: internal_headers, as: :json

        expect(json_response_data['count']).to eq(2)
        expect(json_response_data['remaining']).to eq(1)
        cursor = json_response_data['cursor']
        expect(cursor).to eq(files.map(&:id).sort[1])

        delete "/api/v1/internal/accounts/#{account.id}/files",
               params: { batch_size: 2, after_id: cursor }, headers: internal_headers, as: :json

        expect(json_response_data['count']).to eq(1)
        expect(json_response_data['remaining']).to eq(0)
      end

      it 'records the outcome in the audit row' do
        create(:file_object, account: account, storage: storage, uploaded_by: owner)

        delete "/api/v1/internal/accounts/#{account.id}/files", headers: internal_headers, as: :json

        row = AuditLog.find_by(account_id: account.id, action: 'account.delete_files')
        expect(row.metadata['records_deleted']).to eq(1)
        expect(row.metadata['erased']).to be true
      end

      it 'rejects a malformed cursor with 422 rather than a 500 that would revert a termination' do
        file = create(:file_object, account: account, storage: storage, uploaded_by: owner)

        delete "/api/v1/internal/accounts/#{account.id}/files",
               params: { after_id: 'not-a-uuid' }, headers: internal_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(FileManagement::Object.exists?(file.id)).to be true
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/api_keys' do
    before do
      create_list(:api_key, 3, account: account, created_by: owner)
    end

    context 'with internal authentication' do
      it 'deletes account API keys' do
        delete "/api/v1/internal/accounts/#{account.id}/api_keys", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
        expect(account.api_keys.count).to eq(0)
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.delete_api_keys')
        ).to be true
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/webhooks' do
    before do
      create_list(:webhook_endpoint, 2, account: account)
    end

    context 'with internal authentication' do
      it 'deletes account webhooks' do
        delete "/api/v1/internal/accounts/#{account.id}/webhooks", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.delete_webhooks')
        ).to be true
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/data_export_requests' do
    context 'with internal authentication' do
      it 'deletes data export requests' do
        delete "/api/v1/internal/accounts/#{account.id}/data_export_requests", headers: internal_headers, as: :json

        expect_success_response
        # `message` is a sibling of `data` in the envelope (ApiResponse#render_success
        # sets response[:message] independently of response[:data]), and
        # json_response_data already unwraps to the `data` payload — so `message`
        # is read off the full envelope, not off the unwrapped data hash.
        expect(json_response['message']).to include('Deleted')
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.delete_data_export_requests')
        ).to be true
      end
    end

    # IMP-0310a1351dab: account_terminations.data_export_request_id (set by
    # Account::Termination.initiate whenever request_data_export: true is
    # honoured) has no on_delete — a bare `.delete_all` on the referenced
    # export request raised ActiveRecord::InvalidForeignKey for EVERY such
    # termination, and did so on every retry, forever (the export request
    # was never actually deleted, so the next sweep hit the identical crash).
    context 'when an export request is referenced by an account termination (own_export_request_id passed)' do
      # Operator ruling 2026-09-24: delivered = downloaded, or download
      # window elapsed unused. The base fixture here uses the `:downloaded`
      # trait (actually retrieved) so the top-level "deletes it" examples
      # below exercise the DELIVERED case; a merely `:completed` export with
      # an open window and no download is its own dedicated context further
      # down, since that is now explicitly NOT resolved.
      let(:export_request) { create(:data_management_export_request, :downloaded, account: account, user: owner) }
      let!(:termination) do
        Account::Termination.create!(
          account: account, status: 'grace_period', requested_at: 31.days.ago,
          grace_period_ends_at: 1.day.ago, data_export_request: export_request
        )
      end

      def delete_own_export_requests(own_id)
        delete "/api/v1/internal/accounts/#{account.id}/data_export_requests",
               params: { own_export_request_id: own_id }, headers: internal_headers, as: :json
      end

      it 'deletes the delivered (downloaded) export without raising, and clears the referencing FK' do
        expect { delete_own_export_requests(export_request.id) }.not_to raise_error

        expect_success_response
        expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
        expect(termination.reload.data_export_request_id).to be_nil
      end

      it 'preserves the export\'s own audit trail (its request/completion AuditLog rows are untouched)' do
        # log_export_requested + log_export_completed, written by the
        # ExportRequest factory's :completed trait via #complete! — neither
        # is keyed on the FK or the termination, so deleting either must
        # never remove them.
        export_audit_count = AuditLog.where(resource_type: 'DataManagement::ExportRequest', resource_id: export_request.id).count
        expect(export_audit_count).to be_positive

        delete_own_export_requests(export_request.id)

        expect(
          AuditLog.where(resource_type: 'DataManagement::ExportRequest', resource_id: export_request.id).count
        ).to eq(export_audit_count)
      end

      it 'removes the PII export file from disk' do
        exports_base = Dir.mktmpdir('export-cleanup-test')
        allow(DataManagement::ExportRequest).to receive(:exports_base).and_return(exports_base)
        path = File.join(exports_base, 'export.json')
        File.write(path, 'exported data')
        export_request.update_column(:file_path, path)

        delete_own_export_requests(export_request.id)

        expect(File.exist?(path)).to be false
      ensure
        FileUtils.rm_rf(exports_base) if exports_base
      end

      # IMP-bdd811725d38: file_path is written by a worker principal, so the
      # sweep removes nothing whose real path is outside the exports base.
      it 'removes no file outside the exports base, and still deletes the row' do
        exports_base = Dir.mktmpdir('export-cleanup-base')
        allow(DataManagement::ExportRequest).to receive(:exports_base).and_return(exports_base)
        outside = Tempfile.new('export-cleanup-outside')
        outside.close
        export_request.update_column(:file_path, outside.path)

        delete_own_export_requests(export_request.id)

        expect_success_response
        expect(File.exist?(outside.path)).to be true
        expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
      ensure
        outside&.unlink
        FileUtils.rm_rf(exports_base) if exports_base
      end

      # The archive lives on the WORKER host, which this action cannot reach:
      # it reports the paths of the rows it deleted so the worker removes them.
      it 'reports the archive path of the row it deleted, read before the path is cleared' do
        real_file = Tempfile.new('export-report-test')
        real_file.close
        export_request.update_column(:file_path, real_file.path)

        delete_own_export_requests(export_request.id)

        expect(json_response_data['file_paths']).to eq([ real_file.path ])
      ensure
        real_file&.unlink
      end

      it 'reports no archive paths when the deleted rows have none' do
        export_request.update_column(:file_path, nil)

        delete_own_export_requests(export_request.id)

        expect(json_response_data['file_paths']).to eq([])
      end

      # A file this process cannot remove (another uid on a shared tmp, say)
      # must not turn the termination's sweep into a permanent 500.
      it 'still deletes the row and answers 200 when the archive cannot be removed' do
        exports_base = Dir.mktmpdir('export-eacces-test')
        allow(DataManagement::ExportRequest).to receive(:exports_base).and_return(exports_base)
        path = File.join(exports_base, 'export.json')
        File.write(path, 'exported data')
        export_request.update_column(:file_path, path)
        allow(FileUtils).to receive(:rm_f)

        expect { delete_own_export_requests(export_request.id) }.not_to raise_error

        expect_success_response
        expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
        expect(json_response_data['file_paths']).to eq([ path ])
      ensure
        FileUtils.rm_rf(exports_base) if exports_base
      end

      context 'and the export has not yet been delivered (still pending)' do
        let(:export_request) { create(:data_management_export_request, :pending, account: account, user: owner) }

        it 'defers deletion instead of removing an undelivered export, and reports it' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          # json_response_data already unwraps the envelope's `data` key
          # (render_success(data: { deferred: })), so the value is directly
          # at 'deferred', not nested under a second 'data' key.
          expect(json_response_data['deferred']).to eq(1)
          expect(json_response_data['count']).to eq(0)
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be true
          expect(termination.reload.data_export_request_id).to eq(export_request.id)
        end
      end

      # Operator ruling 2026-09-24: a 'failed' export is NOT resolved for
      # deletion — this replaces the BLOCKER the review flagged ('failed'
      # used to count as ready unconditionally). It has delivered nothing;
      # Compliance::AccountTerminationJob is responsible for resetting it to
      # 'pending' and re-queuing generation (bounded, then parking the
      # termination), not this endpoint quietly letting it through.
      context 'and the export has failed (nothing delivered yet — the worker must retry, not this endpoint)' do
        let(:export_request) { create(:data_management_export_request, :failed, account: account, user: owner) }

        it 'defers deletion rather than treating a failed generation as nothing-left-to-deliver' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          expect(json_response_data['deferred']).to eq(1)
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be true
          expect(termination.reload.data_export_request_id).to eq(export_request.id)
        end
      end

      context 'and the export has expired (the download window has passed — given up)' do
        let(:export_request) { create(:data_management_export_request, :expired, account: account, user: owner) }

        it 'deletes it and clears the referencing FK, the same as a delivered export' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
          expect(termination.reload.data_export_request_id).to be_nil
        end
      end

      # Operator ruling 2026-09-24: 'completed' alone is NOT resolved — the
      # user gets the full 7-day download window before the row (and the
      # account behind it) can be removed.
      context 'and the export is completed but has not yet been downloaded (window still open)' do
        let(:export_request) { create(:data_management_export_request, :completed, account: account, user: owner) }

        it 'defers deletion instead of removing an export the user has not yet retrieved' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          expect(json_response_data['deferred']).to eq(1)
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be true
          expect(termination.reload.data_export_request_id).to eq(export_request.id)
        end
      end

      # Operator ruling 2026-09-24, part (b): the download window elapsing
      # UNUSED (no downloaded_at, but download_token_expires_at has passed)
      # is delivery-resolved on its own — status stays 'completed', it never
      # transitions to 'expired' on its own (that only happens via the
      # explicit expire_export action), but nothing further can be
      # delivered either way.
      context "and the export's download window elapsed with nothing downloaded" do
        let(:export_request) { create(:data_management_export_request, :download_expired, account: account, user: owner) }

        it 'deletes it and clears the referencing FK — the elapsed window is itself resolution' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
          expect(termination.reload.data_export_request_id).to be_nil
        end
      end

      # IMP-0310a1351dab review round 2, HIGH: round 1's own first attempt
      # deferred on ANY pending/processing export anywhere in the account —
      # an UNRELATED self-service export (never linked to this termination
      # via data_export_request_id) silently blocked deletion of every OTHER
      # export too, for every account that happened to have one pending.
      context 'and the account also has an unrelated pending export (not this termination\'s own)' do
        let!(:unrelated_pending) { create(:data_management_export_request, :pending, account: account, user: owner) }

        it 'still deletes the unrelated export (only the termination\'s OWN export can be deferred)' do
          delete_own_export_requests(export_request.id)

          expect_success_response
          expect(json_response_data['deferred']).to eq(0)
          # Producer-side contract: Compliance::AccountTerminationJob#delete_account_records
          # reads this structured `count` to decide whether to log
          # 'deleted_export_requests' at all — it must reflect what was
          # actually deleted (2 here: the termination's own export plus the
          # unrelated one), not be silently absent.
          expect(json_response_data['count']).to eq(2)
          expect(DataManagement::ExportRequest.exists?(unrelated_pending.id)).to be false
          expect(DataManagement::ExportRequest.exists?(export_request.id)).to be false
        end
      end
    end

    context 'when no own_export_request_id is passed (no active termination, or a caller with no export context)' do
      let!(:some_pending) { create(:data_management_export_request, :pending, account: account, user: owner) }

      it 'deletes every export request for the account regardless of status (nothing exempted)' do
        delete "/api/v1/internal/accounts/#{account.id}/data_export_requests", headers: internal_headers, as: :json

        expect_success_response
        expect(json_response_data['deferred']).to eq(0)
        expect(DataManagement::ExportRequest.exists?(some_pending.id)).to be false
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/data_deletion_requests' do
    context 'with internal authentication' do
      it 'deletes data deletion requests' do
        delete "/api/v1/internal/accounts/#{account.id}/data_deletion_requests", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
        expect(
          AuditLog.exists?(account_id: account.id, action: 'account.delete_data_deletion_requests')
        ).to be true
      end
    end
  end
end
