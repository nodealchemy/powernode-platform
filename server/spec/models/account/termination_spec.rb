# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account::Termination, type: :model do
  let(:account) { create(:account) }
  let!(:owner) { create(:user, account: account) }

  # notify_account_users (after_create) ALWAYS sends email via
  # NotificationService, regardless of request_data_export — irrelevant to
  # what this file tests. Stubbed as a no-op rather than mocked through
  # WorkerApiClient: NotificationService.worker_client memoizes
  # `@worker_client` on the CLASS (`class << self`), so a WorkerApiClient
  # double created in one example silently leaks into the next
  # (ExpiredTestDoubleError) — a pre-existing test-isolation hazard in that
  # service, unrelated to this fix, that this spec sidesteps rather than
  # tries to fix.
  before do
    allow(NotificationService).to receive(:send_email)
  end

  describe '.initiate' do
    context 'with request_data_export: true' do
      let(:worker_api_client) { instance_double(WorkerApiClient, queue_job: { 'success' => true }) }

      before do
        allow(WorkerApiClient).to receive(:new).and_return(worker_api_client)
      end

      # IMP-0310a1351dab: DataExportRequestsController#create is the ONLY
      # OTHER writer of a DataManagement::ExportRequest, and it queues
      # Compliance::DataExportJob right after saving. This class method
      # saves the export request directly (ActiveRecord, bypassing that
      # controller), so before this fix the export never ran at all — it
      # sat "pending" forever, which (combined with the termination job's
      # new pre-deletion export-readiness gate) meant a termination that
      # asked for an export could never complete, silently, for the
      # lifetime of the account.
      it 'queues Compliance::DataExportJob for the created export request' do
        termination = described_class.initiate(account: account, requested_by: owner, request_data_export: true)

        expect(worker_api_client).to have_received(:queue_job)
          .with('Compliance::DataExportJob', [ termination.data_export_request_id ], queue: 'compliance')
      end

      it 'does not block termination initiation when queueing the export job fails' do
        allow(worker_api_client).to receive(:queue_job).and_raise(WorkerApiClient::ApiError, 'worker down')

        expect { described_class.initiate(account: account, requested_by: owner, request_data_export: true) }
          .not_to raise_error
      end
    end

    context 'with request_data_export: false' do
      it 'never touches WorkerApiClient' do
        expect(WorkerApiClient).not_to receive(:new)

        described_class.initiate(account: account, requested_by: owner, request_data_export: false)
      end
    end
  end
end
