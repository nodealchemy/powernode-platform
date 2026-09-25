# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataExportRequests', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  # Stub out side-effects globally
  before do
    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
    allow(AuditLog).to receive(:log_compliance_event).and_return(true)
    allow(AuditLog).to receive(:log_action).and_return(true)
    allow(NotificationService).to receive(:send_email).and_return(true)

    # The controller dispatches processing through the worker HTTP API seam
    allow(WorkerApiClient).to receive(:new).and_return(worker_api_client)
  end

  let(:worker_api_client) do
    instance_double(WorkerApiClient, queue_job: { 'success' => true })
  end

  # Helper to create export request
  let(:create_export_request) do
    ->(attrs = {}) {
      DataManagement::ExportRequest.create!({
        account: account,
        user: user,
        format: 'json',
        export_type: 'full',
        status: 'pending'
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/data_export_requests/:id' do
    let(:export_request) { create_export_request.call }

    context 'with internal authentication' do
      it 'returns export request details' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['data_export_request']).to include(
          'id' => export_request.id,
          'status' => 'pending'
        )
      end

      it 'includes detailed fields' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['data_export_request']).to have_key('include_data_types')
      end

      # IMP-0310a1351dab: PRODUCER-SIDE CONTRACT for Compliance::DataExportJob
      # (the sole consumer of this endpoint). That job reads
      # `response.dig('data', 'data_export_request', 'status')` — before this
      # fix it read `response['data']['status']` instead, which is always nil
      # against this envelope (the record is nested one level deeper), so the
      # job's `unless status == 'pending'` guard always took the skip branch
      # and the export was never actually processed, ever. Pinned at the
      # exact path a consumer would dig, not just "the key exists somewhere
      # in the response" — a regression back to a flatter shape must fail
      # THIS assertion, not just leave `have_key` (above) still vacuously
      # true against a differently-nested response.
      it "nests the record under data.data_export_request — the exact path DataExportJob reads" do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'status')).to eq('pending')
        expect(json_response.dig('data', 'data_export_request', 'id')).to eq(export_request.id)
      end

      # IMP-0310a1351dab review round 2, items 3+6: PRODUCER-SIDE CONTRACT for
      # Compliance::AccountTerminationJob#export_ready_for_deletion?, the
      # worker's pre-deletion gate. It reads THIS field rather than
      # re-deriving the delivery rule itself — a regression dropping the
      # field (or reverting DataManagement::ExportRequest#delivered_for_deletion?)
      # must fail here, not only be caught by a stubbed worker spec that
      # can't see the real server response shape.
      #
      # Operator ruling 2026-09-24: delivered = downloaded, or download
      # window elapsed unused. Covers all four cases the ruling names.
      it 'exposes delivered_for_deletion — false for a still-pending export' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(false)
      end

      it 'exposes delivered_for_deletion — false for a completed export with an open, undownloaded window' do
        export_request.update!(
          status: 'completed', completed_at: Time.current,
          download_token: SecureRandom.urlsafe_base64(32), download_token_expires_at: 7.days.from_now
        )

        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(false)
      end

      it 'exposes delivered_for_deletion — true once the export has actually been downloaded' do
        export_request.update!(
          status: 'completed', completed_at: Time.current,
          download_token: SecureRandom.urlsafe_base64(32), download_token_expires_at: 7.days.from_now,
          downloaded_at: Time.current
        )

        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(true)
      end

      it 'exposes delivered_for_deletion — true once the download window has elapsed unused' do
        export_request.update!(
          status: 'completed', completed_at: Time.current,
          download_token: SecureRandom.urlsafe_base64(32), download_token_expires_at: 1.day.ago
        )

        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(true)
      end

      it 'exposes delivered_for_deletion — true for the explicit expired status' do
        export_request.update!(status: 'expired', download_token: nil, download_token_expires_at: nil)

        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(true)
      end

      it 'exposes delivered_for_deletion — false for a failed export (nothing delivered; the worker must retry)' do
        export_request.update!(status: 'failed', completed_at: Time.current, error_message: 'boom')

        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect(json_response.dig('data', 'data_export_request', 'delivered_for_deletion')).to eq(false)
      end
    end

    context 'when request does not exist' do
      it 'returns not found error' do
        get "/api/v1/internal/data_export_requests/#{SecureRandom.uuid}", headers: internal_headers, as: :json

        expect_error_response('Data export request not found', 404)
      end
    end
  end

  describe 'POST /api/v1/internal/data_export_requests' do
    let(:valid_params) do
      {
        data_export_request: {
          account_id: account.id,
          user_id: user.id,
          format: 'json',
          include_data_types: [ 'profile', 'activity', 'audit_logs' ]
        }
      }
    end

    context 'with internal authentication' do
      it 'creates a new export request' do
        expect {
          post '/api/v1/internal/data_export_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::ExportRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['data_export_request']['status']).to eq('pending')
      end

      it 'queues Compliance::DataExportJob through the worker API seam' do
        post '/api/v1/internal/data_export_requests', params: valid_params, headers: internal_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(worker_api_client).to have_received(:queue_job)
          .with('Compliance::DataExportJob', [ DataManagement::ExportRequest.order(:created_at).last.id ], queue: 'compliance')
      end

      it 'still succeeds when the worker API is unavailable' do
        allow(worker_api_client).to receive(:queue_job)
          .and_raise(WorkerApiClient::ApiError, 'worker down')

        expect {
          post '/api/v1/internal/data_export_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::ExportRequest, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_export_requests/:id' do
    let(:export_request) { create_export_request.call(status: 'pending') }

    context 'with action_type: start' do
      it 'starts export processing' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('processing')
        expect(worker_api_client).to have_received(:queue_job)
          .with('Compliance::DataExportJob', [ export_request.id ], queue: 'compliance')
      end

      it 'rejects non-pending request' do
        export_request.update!(status: 'processing', processing_started_at: Time.current)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: complete' do
      before { export_request.update!(status: 'processing', processing_started_at: Time.current) }

      it 'completes export' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                action_type: 'complete',
                file_path: '/exports/export-123.zip',
                file_size_bytes: 1024000
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('completed')
      end

      it 'rejects non-processing request' do
        export_request.update!(status: 'pending')

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: fail' do
      before { export_request.update!(status: 'processing', processing_started_at: Time.current) }

      it 'marks export as failed' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'fail', error_message: 'Export processing failed' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('failed')
      end

      # IMP-0310a1351dab review round 4, item 4 (LOW): the bounded retry this
      # fix introduced (Compliance::AccountTerminationJob's handle_failed_export!
      # / handle_stale_processing_export!) routes every subsequent failure of
      # the SAME export back through this same action, up to
      # EXPORT_DELIVERY_RETRY_LIMIT + 1 times — the user should hear about
      # the FIRST one, not get a repeat "your export failed" email for every
      # internal retry attempt.
      it 'notifies the user on the first failure' do
        expect(NotificationService).to receive(:send_email)
          .with(hash_including(template: 'data_export_failed'))

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'fail', error_message: 'Export processing failed' },
              headers: internal_headers,
              as: :json
      end

      it 'does not notify the user again on a later retry\'s failure' do
        export_request.update!(metadata: { 'delivery_retry_count' => 1 })

        expect(NotificationService).not_to receive(:send_email)
          .with(hash_including(template: 'data_export_failed'))

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'fail', error_message: 'Export processing failed again' },
              headers: internal_headers,
              as: :json

        expect_success_response
        expect(export_request.reload.status).to eq('failed')
      end
    end

    context 'with action_type: expire' do
      before do
        export_request.update!(
          status: 'completed',
          completed_at: Time.current,
          file_path: '/tmp/test-export.zip'
        )
      end

      it 'expires export' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'expire' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('expired')
      end
    end

    # IMP-0310a1351dab review round 2, item 6 (operator ruling 2026-09-24):
    # Compliance::AccountTerminationJob resets a failed export through this
    # action rather than deleting/ignoring it — retried, bounded generation,
    # never a silent "nothing left to deliver".
    context 'with action_type: retry' do
      before do
        export_request.update!(
          status: 'failed', completed_at: Time.current, error_message: 'boom',
          processing_started_at: 30.minutes.ago
        )
      end

      it 'resets the export to pending, clearing the prior error and timestamp' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'retry' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('pending')
        expect(export_request.error_message).to be_nil
        expect(export_request.processing_started_at).to be_nil
      end

      it 'tracks a bounded, incrementing retry count in metadata' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'retry' },
              headers: internal_headers,
              as: :json

        expect(json_response.dig('data', 'data_export_request', 'metadata', 'delivery_retry_count')).to eq(1)

        # `.reload` first: this in-memory object's own `status` attribute is
        # still the ORIGINAL "failed" it was created with (the first PATCH
        # above wrote 'pending' through a DIFFERENT ActiveRecord instance,
        # fetched fresh by the controller's own `set_export_request`) — a
        # bare `update!(status: 'failed')` against a value AR already
        # believes is current is a dirty-tracking no-op that issues no SQL,
        # silently leaving the real row 'pending'.
        export_request.reload.update!(status: 'failed')
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'retry' },
              headers: internal_headers,
              as: :json

        expect(json_response.dig('data', 'data_export_request', 'metadata', 'delivery_retry_count')).to eq(2)
      end

      it 'rejects retrying a non-failed export' do
        export_request.update!(status: 'pending')

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'retry' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
