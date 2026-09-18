# frozen_string_literal: true

require 'rails_helper'

# Fix constant resolution: Api::V1::Internal::DataManagement module (from the namespaced
# controllers directory) shadows the top-level DataManagement module. Define the expected
# constants so the controller can resolve DataManagement::* correctly within its namespace.
unless defined?(Api::V1::Internal::DataManagement::DeletionRequest)
  Api::V1::Internal::DataManagement::DeletionRequest = ::DataManagement::DeletionRequest
end

RSpec.describe 'Api::V1::Internal::DataDeletionRequests', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, account: account) }

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
    allow(Notification).to receive(:create).and_return(Notification.new)

    # The controller dispatches processing through the worker HTTP API seam
    allow(WorkerApiClient).to receive(:new).and_return(worker_api_client)
  end

  let(:worker_api_client) do
    instance_double(WorkerApiClient, queue_job: { 'success' => true })
  end

  # Helper to create deletion request
  let(:create_deletion_request) do
    ->(attrs = {}) {
      DataManagement::DeletionRequest.create!({
        account: account,
        user: user,
        deletion_type: 'full',
        reason: 'User requested account deletion',
        status: 'pending'
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call }

    context 'with internal authentication' do
      it 'returns deletion request details' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['data_deletion_request']).to include(
          'id' => deletion_request.id,
          'deletion_type' => 'full',
          'status' => 'pending'
        )
      end

      it 'includes detailed fields' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['data_deletion_request']).to have_key('data_types_to_delete')
        expect(data['data_deletion_request']).to have_key('reason')
      end
    end

    context 'when request does not exist' do
      it 'returns not found error' do
        get "/api/v1/internal/data_deletion_requests/#{SecureRandom.uuid}", headers: internal_headers, as: :json

        expect_error_response('Data deletion request not found', 404)
      end
    end
  end

  describe 'POST /api/v1/internal/data_deletion_requests' do
    let(:valid_params) do
      {
        data_deletion_request: {
          account_id: account.id,
          user_id: user.id,
          deletion_type: 'full',
          reason: 'GDPR deletion request',
          data_types_to_delete: [ 'profile', 'activity', 'audit_logs' ]
        }
      }
    end

    context 'with internal authentication' do
      it 'creates a new deletion request' do
        expect {
          post '/api/v1/internal/data_deletion_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::DeletionRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['data_deletion_request']['status']).to eq('pending')
      end

      it 'queues Compliance::DataDeletionJob through the worker API seam' do
        post '/api/v1/internal/data_deletion_requests', params: valid_params, headers: internal_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(worker_api_client).to have_received(:queue_job)
          .with('Compliance::DataDeletionJob',
                [ DataManagement::DeletionRequest.order(:created_at).last.id ],
                queue: 'compliance')
      end

      it 'still succeeds when the worker API is unavailable' do
        allow(worker_api_client).to receive(:queue_job)
          .and_raise(WorkerApiClient::ApiError, 'worker down')

        expect {
          post '/api/v1/internal/data_deletion_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::DeletionRequest, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call(status: 'pending') }

    context 'with action_type: approve' do
      it 'approves deletion request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve', processed_by_id: admin_user.id },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('approved')

        # S-B (IMP-b33a3ecca331 third review): this used to omit
        # grace_period_ends_at entirely, unlike the model's own #approve!
        # (unused by this controller) which sets it. Compliance::
        # DataDeletionJob reads this unconditionally once a request is
        # approved/processing and crashed on Time.zone.parse(nil) for every
        # request approved through this — the only approval path that
        # exists.
        expect(deletion_request.grace_period_ends_at).to be_present
        expect(deletion_request.grace_period_ends_at).to be_within(1.minute).of(
          DataManagement::DeletionRequest::GRACE_PERIOD_DAYS.days.from_now
        )

        # IMP-26a95cba1d43: log_internal_audit("data_deletion.approve", ...)
        # was never registered in AuditActions — AuditLog.create! raised
        # ActiveRecord::RecordInvalid and the rescue silently dropped the
        # row (this endpoint returns 200 regardless). Assert the row EXISTS
        # with the exact action, not just that the status transitioned.
        expect(
          AuditLog.exists?(action: 'data_deletion.approve', resource_id: deletion_request.id)
        ).to be true
      end

      it 'rejects non-pending request' do
        deletion_request.update!(status: 'processing', processing_started_at: Time.current)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: reject' do
      it 'rejects deletion request with reason' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                action_type: 'reject',
                reason: 'Request does not meet criteria',
                rejected_by_id: admin_user.id
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('rejected')
        expect(
          AuditLog.exists?(action: 'data_deletion.reject', resource_id: deletion_request.id)
        ).to be true
      end

      it 'requires rejection reason' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'reject' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: execute' do
      before do
        deletion_request.update!(
          status: 'approved',
          approved_at: Time.current,
          processed_by_id: admin_user.id
        )
      end

      it 'starts deletion execution' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('processing')
        expect(worker_api_client).to have_received(:queue_job)
          .with('Compliance::DataDeletionJob', [ deletion_request.id ], queue: 'compliance')
        expect(
          AuditLog.exists?(action: 'data_deletion.execute', resource_id: deletion_request.id)
        ).to be true
      end

      it 'rejects non-approved request' do
        deletion_request.update!(status: 'pending')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: complete' do
      before do
        deletion_request.update!(
          status: 'processing',
          processing_started_at: Time.current
        )
      end

      it 'completes deletion' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                action_type: 'complete',
                deletion_log: [ { type: 'profile', count: 1 }, { type: 'activities', count: 100 }, { type: 'files', count: 49 } ]
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('completed')
        expect(
          AuditLog.exists?(action: 'data_deletion.complete', resource_id: deletion_request.id)
        ).to be true
      end

      it 'rejects non-processing request' do
        deletion_request.update!(status: 'pending')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # IMP-b33a3ecca331: Compliance::DataDeletionJob PATCHes this endpoint with a
  # raw top-level JSON body (no `data_deletion_request:` wrapper — the app is
  # ActionController::API, no ParamsWrapper) and never sets `action_type`, so
  # every one of these calls falls into the generic `else` branch. That branch
  # used to `params.require(:data_deletion_request)`, which raised
  # ActionController::ParameterMissing on a body shaped exactly like this —
  # rescued into a 400 the job never checked, so none of these writes ever
  # actually persisted. Sends the exact raw, job-shaped bodies.
  describe 'PATCH /api/v1/internal/data_deletion_requests/:id (raw job-shaped body, no action_type)' do
    let(:deletion_request) { create_deletion_request.call(status: 'approved') }

    it 'persists a processing-start status transition' do
      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'processing', processing_started_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect_success_response

      deletion_request.reload
      expect(deletion_request.status).to eq('processing')
      expect(deletion_request.processing_started_at).to be_present
    end

    it 'persists a completed transition with deletion_log and retention_log' do
      deletion_request.update!(status: 'processing', processing_started_at: Time.current)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: {
              status: 'completed',
              completed_at: Time.current.iso8601,
              deletion_log: [
                { data_type: 'consents', action: 'deleted', records_affected: 2, processed_at: Time.current.iso8601 },
                { data_type: 'profile', action: 'anonymized', processed_at: Time.current.iso8601 }
              ],
              retention_log: [
                { data_type: 'financial_records', reason: 'Required for tax and accounting purposes',
                  processed_at: Time.current.iso8601 }
              ]
            },
            headers: internal_headers,
            as: :json

      expect_success_response

      deletion_request.reload
      expect(deletion_request.status).to eq('completed')
      expect(deletion_request.completed_at).to be_present
      expect(deletion_request.deletion_log.size).to eq(2)
      expect(deletion_request.deletion_log.first).to include('data_type' => 'consents', 'action' => 'deleted')
      expect(deletion_request.retention_log.size).to eq(1)
    end

    it 'persists a failed transition with error_message and a skipped-type log entry' do
      deletion_request.update!(status: 'processing', processing_started_at: Time.current)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: {
              status: 'failed',
              error_message: 'Data deletion failed for: files',
              deletion_log: [
                { data_type: 'files', action: 'skipped', reason: 'no_backing_data_model',
                  processed_at: Time.current.iso8601 }
              ]
            },
            headers: internal_headers,
            as: :json

      expect_success_response

      deletion_request.reload
      expect(deletion_request.status).to eq('failed')
      expect(deletion_request.error_message).to eq('Data deletion failed for: files')
      expect(deletion_request.deletion_log.first).to include('action' => 'skipped', 'reason' => 'no_backing_data_model')
    end

    it 'rejects an unsupported status value (model inclusion validation still applies)' do
      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'not_a_real_status' },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)

      deletion_request.reload
      expect(deletion_request.status).to eq('approved')
    end
  end

  # SECURITY-RELEVANT (IMP-b33a3ecca331 review, S3): before this fix, the raw
  # (no action_type) branch let ANY mTLS-enrolled worker principal set ANY
  # valid model status via this one generic PATCH — including `completed` on
  # a request that was never approved, bypassing complete_request's own
  # `processing?` guard, its audit row, and its user notification. That would
  # forge a GDPR completion record for a request nobody ever authorized.
  describe 'PATCH /api/v1/internal/data_deletion_requests/:id status-transition guard (raw body)' do
    it 'rejects pending -> completed (the forged-completion scenario)' do
      deletion_request = create_deletion_request.call(status: 'pending')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'completed', completed_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

      deletion_request.reload
      expect(deletion_request.status).to eq('pending')
    end

    it 'rejects approved -> completed (skipping processing entirely)' do
      deletion_request = create_deletion_request.call(status: 'approved')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'completed', completed_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)

      deletion_request.reload
      expect(deletion_request.status).to eq('approved')
    end

    it 'rejects failed -> completed (no re-arm path for a terminal request)' do
      deletion_request = create_deletion_request.call(status: 'failed')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'completed', completed_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)

      deletion_request.reload
      expect(deletion_request.status).to eq('failed')
    end

    it 'allows approved -> processing and writes a data_deletion.status_transition audit row' do
      deletion_request = create_deletion_request.call(status: 'approved')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'processing', processing_started_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect_success_response
      deletion_request.reload
      expect(deletion_request.status).to eq('processing')
      expect(
        AuditLog.exists?(action: 'data_deletion.status_transition', resource_id: deletion_request.id)
      ).to be true
    end

    it 'allows processing -> processing (a retry resuming a request left mid-flight)' do
      deletion_request = create_deletion_request.call(status: 'processing', processing_started_at: Time.current)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'processing', processing_started_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect_success_response
      deletion_request.reload
      expect(deletion_request.status).to eq('processing')
    end

    # S-B (IMP-b33a3ecca331 third review): the job's grace_period_ends_at
    # nil-guard fires BEFORE the 'processing' write (deliberately, so a
    # request still legitimately waiting out its grace period is never
    # marked 'processing') — so it needs to terminally fail an 'approved'
    # request directly, which the transition map didn't allow before.
    it 'allows approved -> failed (the grace_period_ends_at nil-guard path)' do
      deletion_request = create_deletion_request.call(status: 'approved', grace_period_ends_at: nil)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'failed', error_message: 'Deletion request has no grace_period_ends_at set' },
            headers: internal_headers,
            as: :json

      expect_success_response
      deletion_request.reload
      expect(deletion_request.status).to eq('failed')
    end

    # Fourth review, nit 3: the guard above is conditioned on the actual
    # data-integrity defect it exists for, not a general approved -> failed
    # escape hatch — when grace_period_ends_at IS present, this must still be
    # rejected the same as any other unlisted transition.
    it 'rejects approved -> failed when grace_period_ends_at is present (not a general escape hatch)' do
      deletion_request = create_deletion_request.call(status: 'approved', grace_period_ends_at: 5.days.from_now)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { status: 'failed', error_message: 'should not be allowed' },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

      deletion_request.reload
      expect(deletion_request.status).to eq('approved')
    end
  end

  # Nit (IMP-b33a3ecca331 third review): a status-less PATCH carrying
  # progress fields (completed_at/deletion_log/retention_log/error_message)
  # is a status-ADJACENT write, meaningful only while the request is actively
  # 'processing' — an 'approved' request has no run in flight to report
  # progress for.
  describe 'PATCH /api/v1/internal/data_deletion_requests/:id status-less progress writes' do
    it 'rejects a status-less error_message write while still approved' do
      deletion_request = create_deletion_request.call(status: 'approved', processing_started_at: nil)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { error_message: 'should not be accepted yet' },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

      deletion_request.reload
      expect(deletion_request.error_message).to be_nil
    end

    it 'allows a status-less deletion_log write while processing' do
      deletion_request = create_deletion_request.call(status: 'processing', processing_started_at: Time.current)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: {
              deletion_log: [
                { data_type: 'consents', action: 'deleted', records_affected: 2, processed_at: Time.current.iso8601 }
              ]
            },
            headers: internal_headers,
            as: :json

      expect_success_response
      deletion_request.reload
      expect(deletion_request.deletion_log.first).to include('data_type' => 'consents', 'action' => 'deleted')
    end

    # Fourth review, nit 3: metadata is now a status-adjacent key too (no real
    # caller — job or admin action — sends a status-less metadata write while
    # NOT processing, so it's guarded the same as the rest rather than left
    # as an unrestricted escape hatch).
    it 'rejects a status-less metadata write while still approved' do
      deletion_request = create_deletion_request.call(status: 'approved')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { metadata: { note: 'should not be accepted yet' } },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')
    end

    it 'allows a status-less metadata write while processing' do
      deletion_request = create_deletion_request.call(status: 'processing', processing_started_at: Time.current)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { metadata: { note: 'in flight' } },
            headers: internal_headers,
            as: :json

      expect_success_response
      deletion_request.reload
      expect(deletion_request.metadata).to include('note' => 'in flight')
    end

    # processing_started_at also joined STATUS_ADJACENT_KEYS this round —
    # every real caller sends it paired WITH status: 'processing' (a
    # status-present write, a different branch entirely), never status-less,
    # so guarding it costs no real coverage.
    it 'rejects a status-less processing_started_at write while still approved' do
      deletion_request = create_deletion_request.call(status: 'approved')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { processing_started_at: Time.current.iso8601 },
            headers: internal_headers,
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')
    end

    it 'still allows a genuinely bare write (no status-adjacent keys at all) regardless of status' do
      deletion_request = create_deletion_request.call(status: 'approved')

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: {},
            headers: internal_headers,
            as: :json

      expect_success_response
    end
  end

  # IMP-26a95cba1d43 — the swallowed-write decision on the irreversible
  # personal-data deletion path. Simulates the exact defect this task fixed
  # (an unregistered action literal reaching log_internal_audit) by revoking
  # registration for one already-valid literal, WITHOUT touching the real
  # AuditActions registry the rest of the suite relies on. Proves both halves
  # of the decision: (a) a durable, self-referential "audit_logging_error"
  # row is written every time (never silently drop the failure), and (b) the
  # request environment surfaces the failure instead of returning 200 with
  # nothing to show for it.
  #
  # HOW THE 422 ACTUALLY HAPPENS (review correction, IMP-26a95cba1d43 D5): an
  # earlier version of this comment blamed
  # `config.action_dispatch.show_exceptions = :rescuable` and said "no local
  # rescue_from is involved" — that was wrong, and worse, it pointed a future
  # debugger at the wrong lever. The real mechanism: ApiResponse (included
  # into ApplicationController) registers `rescue_from ActiveRecord::
  # RecordInvalid` (app/controllers/concerns/api_response.rb) which calls
  # `render_validation_error(exception.record.errors)` — the exception never
  # leaves the controller at all. That same `included do` block also has a
  # catch-all `rescue_from StandardError` (defined first, so lower priority
  # per rescue_from's "last defined wins" rule) — so a re-raised failure that
  # is NOT an ActiveRecord::RecordInvalid (e.g. some other write error) would
  # surface as a generic 500 body via that handler instead of a 422 naming
  # the field, a different shape than this example asserts.
  describe 'when the underlying audit write is rejected (unregistered action literal)' do
    let(:deletion_request) { create_deletion_request.call(status: 'pending') }

    before do
      allow(AuditActions).to receive(:all_actions)
        .and_return(AuditActions.all_actions - [ 'data_deletion.approve' ])
    end

    it 'surfaces the failure as an error response and writes a durable audit_logging_error row' do
      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { action_type: 'approve', processed_by_id: admin_user.id },
            headers: internal_headers,
            as: :json

      # Not a silent 200 — the broken literal is now visible in the
      # response. Asserted on the stable error CODE and on an attribute-
      # level regex, not the exact full sentence: the exact message is
      # `errors.full_messages.first` (render_validation_error), so it is
      # order-dependent on AuditLog's OTHER validations — had account_id
      # also been unattributable here, the first message would be about
      # the account, not the action, without this test having regressed.
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('VALIDATION_ERROR')
      expect(json_response['details']['errors'].join(' ')).to match(/action/i)

      # The destructive state transition already committed before the audit
      # write was attempted — the response turning into an error does not
      # roll it back.
      expect(deletion_request.reload.status).to eq('approved')

      fallback_row = AuditLog.where(action: 'audit_logging_error').order(:created_at).last
      expect(fallback_row).not_to be_nil
      expect(fallback_row.metadata['original_action']).to eq('data_deletion.approve')
      expect(fallback_row.metadata['original_resource_id']).to eq(deletion_request.id)

      # The row that SHOULD have carried the real event is still absent —
      # this is the "audit silently dropped" state the fallback row exists
      # to make visible, not a substitute for the missing row.
      expect(
        AuditLog.exists?(action: 'data_deletion.approve', resource_id: deletion_request.id)
      ).to be false
    end

    it 'does not raise outside the test environment, but still writes the durable fallback row' do
      # Runs the REAL log_internal_audit (nothing about it is stubbed) with
      # only Rails.env.test? forced false, so this exercises the exact
      # production code path rather than a hand-written reimplementation.
      # This is what makes `raise if Rails.env.test?` in
      # internal_base_controller.rb load-bearing in BOTH directions: making
      # it unconditional (raising in production too) reddens this example;
      # deleting it entirely (back to the pre-fix silent swallow) reddens
      # the example above instead, since the response would stay 200.
      allow(Rails.env).to receive(:test?).and_return(false)

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { action_type: 'approve', processed_by_id: admin_user.id },
            headers: internal_headers,
            as: :json

      expect_success_response
      expect(deletion_request.reload.status).to eq('approved')

      fallback_row = AuditLog.where(action: 'audit_logging_error').order(:created_at).last
      expect(fallback_row).not_to be_nil
      expect(fallback_row.metadata['original_action']).to eq('data_deletion.approve')

      expect(
        AuditLog.exists?(action: 'data_deletion.approve', resource_id: deletion_request.id)
      ).to be false
    end

    it 'does not attribute the fallback row to a guessed account when metadata carries no account_id (D1)' do
      # Simulates the shape of maintenance_controller.rb's own
      # "backup.create" writer (unregistered AND account_id-less; filed
      # separately as IMP-01a0b2f5, not fixed here) without depending on
      # that endpoint: `belongs_to :created_by` on Database::Backup makes
      # create_backup fail before ever reaching log_internal_audit today
      # (confirmed directly; a third, independent, also out-of-scope
      # defect), so it cannot exercise this live. `and_wrap_original` calls
      # through the REAL log_internal_audit with only `account_id` stripped
      # from metadata — the exact branch this task's fix added — rather
      # than replacing the method with a reimplementation.
      other_account = create(:account)

      allow_any_instance_of(Api::V1::Internal::DataDeletionRequestsController)
        .to receive(:log_internal_audit).and_wrap_original do |original, action, resource_type, resource_id, metadata = {}|
          original.call(action, resource_type, resource_id, metadata.except(:account_id))
        end

      patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            params: { action_type: 'approve', processed_by_id: admin_user.id },
            headers: internal_headers,
            as: :json

      # No account can be honestly attributed — zero fallback rows anywhere,
      # not a row guessed onto `other_account` (or any other account).
      expect(AuditLog.where(action: 'audit_logging_error').count).to eq(0)
      expect(AuditLog.where(account_id: other_account.id)).to be_empty
    end
  end
end
