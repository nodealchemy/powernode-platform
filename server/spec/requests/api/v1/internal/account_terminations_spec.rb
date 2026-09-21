# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::AccountTerminations', type: :request do
  let(:account) { create(:account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  # Stub worker job dispatch — termination callbacks trigger notifications via WorkerJobService
  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt-token")
    allow_any_instance_of(WorkerJobService).to receive(:make_worker_request).and_return({ "job_id" => "test" })
  end

  describe 'GET /api/v1/internal/account_terminations' do
    let!(:pending_termination) do
      Account::Termination.create!(
        account: account,
        status: 'pending',
        reason: 'user_requested',
        requested_at: Time.current,
        grace_period_ends_at: 2.days.from_now
      )
    end

    let!(:processing_termination) do
      Account::Termination.create!(
        account: create(:account),
        status: 'processing',
        reason: 'payment_failure',
        grace_period_ends_at: 1.day.ago,
        requested_at: 2.days.ago,
        processing_started_at: 1.hour.ago
      )
    end

    let!(:completed_termination) do
      Account::Termination.create!(
        account: create(:account),
        status: 'completed',
        reason: 'user_requested',
        requested_at: 10.days.ago,
        grace_period_ends_at: 5.days.ago,
        completed_at: 3.days.ago
      )
    end

    context 'with service token authentication' do
      it 'returns active terminations (pending, grace_period, processing)' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data'].size).to eq(2)
        termination_ids = response_data['data'].map { |t| t['id'] }
        expect(termination_ids).to include(pending_termination.id, processing_termination.id)
        expect(termination_ids).not_to include(completed_termination.id)
      end

      it 'returns terminations ordered by grace_period_ends_at ascending' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        response_data = json_response
        terminations = response_data['data']

        expect(terminations.first['id']).to eq(processing_termination.id)
        expect(terminations.last['id']).to eq(pending_termination.id)
      end

      it 'includes all termination fields' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        response_data = json_response
        termination = response_data['data'].first

        expect(termination).to include(
          'id',
          'account_id',
          'status',
          'reason',
          'grace_period_ends_at',
          'processing_started_at',
          'completed_at',
          'requested_at',
          'created_at',
          'updated_at'
        )
      end

      # BLOCKER 2 (IMP-f0560910fa62 review): termination_data never included
      # processing_started_at -- the column exists and PATCH permits writing
      # it, but this READ silently dropped it, so every 'processing' row
      # arrived at the worker looking like it had no processing_started_at
      # at all. Compliance::AccountTerminationJob#stranded_processing_terminations
      # judges every 'processing' row's age off exactly this field; with it
      # always absent, the staleness gate was inert on a perfectly healthy
      # system (every row misjudged as an anomaly, not just old-vs-young).
      # No worker-side spec can ever catch this: every worker spec stubs the
      # API response, so it never talks to this serializer. Only a request
      # spec against the real controller closes the gap.
      it 'includes processing_started_at, the field the worker staleness gate depends on' do
        get '/api/v1/internal/account_terminations', headers: internal_headers, as: :json

        expect_success_response
        termination = json_response['data'].find { |t| t['id'] == processing_termination.id }

        expect(termination['processing_started_at']).to be_present
        expect(Time.zone.parse(termination['processing_started_at']))
          .to be_within(1.second).of(processing_termination.processing_started_at)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/account_terminations', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # SECURITY-CRITICAL (IMP-b33a3ecca331 review, B2): index used to ignore
    # `status`/`grace_period_expired` entirely, so
    # Compliance::AccountTerminationJob#process_ready_terminations — which
    # sends exactly {status: 'grace_period', grace_period_expired: true} —
    # would have received (and irreversibly, destructively processed: user
    # anonymization, API key/webhook deletion, account cancellation) every
    # `pending` (never confirmed by the account owner) and every
    # `grace_period` termination whose 30-day window hasn't even elapsed yet.
    context "with the worker job's ready-for-processing query" do
      let!(:not_yet_expired_termination) do
        Account::Termination.create!(
          account: create(:account),
          status: 'grace_period',
          reason: 'user_requested',
          requested_at: 2.days.ago,
          grace_period_ends_at: 5.days.from_now
        )
      end

      let!(:expired_termination) do
        Account::Termination.create!(
          account: create(:account),
          status: 'grace_period',
          reason: 'user_requested',
          requested_at: 40.days.ago,
          grace_period_ends_at: 10.days.ago
        )
      end

      # `as: :json` is deliberately OMITTED on these four: combined with a
      # non-empty `params:` hash on a GET, it makes this Rails/rack-test
      # version dispatch the request as POST (404, no route) instead of GET —
      # confirmed by hand against the same route with/without `as: :json`.
      # Plain `params:` + `headers:` still exercises the real routing/param
      # parsing and `json_response` still parses the JSON body correctly.
      it 'excludes a pending (never confirmed) termination' do
        get '/api/v1/internal/account_terminations',
            params: { status: 'grace_period', grace_period_expired: true },
            headers: internal_headers

        expect_success_response
        termination_ids = json_response['data'].map { |t| t['id'] }
        expect(termination_ids).not_to include(pending_termination.id)
      end

      it 'excludes a grace_period termination whose window has not expired' do
        get '/api/v1/internal/account_terminations',
            params: { status: 'grace_period', grace_period_expired: true },
            headers: internal_headers

        expect_success_response
        termination_ids = json_response['data'].map { |t| t['id'] }
        expect(termination_ids).not_to include(not_yet_expired_termination.id)
      end

      it 'includes a grace_period termination whose window has expired' do
        get '/api/v1/internal/account_terminations',
            params: { status: 'grace_period', grace_period_expired: true },
            headers: internal_headers

        expect_success_response
        termination_ids = json_response['data'].map { |t| t['id'] }
        expect(termination_ids).to eq([ expired_termination.id ])
      end

      it "the reminder query (status: 'grace_period' alone) returns every grace_period termination, expired or not" do
        get '/api/v1/internal/account_terminations',
            params: { status: 'grace_period' },
            headers: internal_headers

        expect_success_response
        termination_ids = json_response['data'].map { |t| t['id'] }
        expect(termination_ids).to include(not_yet_expired_termination.id, expired_termination.id)
        expect(termination_ids).not_to include(pending_termination.id, processing_termination.id)
      end
    end
  end

  describe 'GET /api/v1/internal/account_terminations/:id' do
    let(:termination) do
      Account::Termination.create!(
        account: account,
        status: 'pending',
        reason: 'user_requested',
        requested_at: Time.current,
        grace_period_ends_at: 2.days.from_now
      )
    end

    context 'with service token authentication' do
      it 'returns termination details' do
        get "/api/v1/internal/account_terminations/#{termination.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => termination.id,
          'account_id' => account.id,
          'status' => 'pending',
          'reason' => 'user_requested'
        )
      end

      it 'includes grace_period_ends_at timestamp' do
        get "/api/v1/internal/account_terminations/#{termination.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        expect(response_data['data']['grace_period_ends_at']).to be_present
      end
    end

    context 'when termination does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/account_terminations/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Account termination not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/account_terminations/#{termination.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # SECURITY (IMP-b33a3ecca331 third review, S-A): the raw (no action_type —
  # this endpoint has no action_type dispatch to begin with, unlike
  # DataDeletionRequestsController) status branch used to accept ANY status
  # value with no transition guard and no audit trail at all. The fixtures
  # below start each termination in whatever status the WORKER (Compliance::
  # AccountTerminationJob) would actually have found it in before making that
  # exact PATCH — pending -> grace_period/completed/cancelled were never
  # transitions the worker sends (those go through the model's own confirm!/
  # cancel!/complete!, called from a different, user-facing surface), so they
  # are no longer exercised as "the worker sends this and it works" cases.
  describe 'PATCH /api/v1/internal/account_terminations/:id' do
    let(:termination) do
      Account::Termination.create!(
        account: account,
        status: 'grace_period',
        reason: 'user_requested',
        requested_at: 31.days.ago,
        grace_period_ends_at: 1.day.ago # expired: can_start_processing? true
      )
    end

    context 'with service token authentication' do
      it 'transitions grace_period -> processing once the grace period has expired' do
        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'processing', processing_started_at: Time.current.iso8601 },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('processing')

        termination.reload
        expect(termination.status).to eq('processing')
      end

      it 'updates termination status to completed with completion timestamp' do
        termination.update!(status: 'processing', processing_started_at: 1.hour.ago)

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: {
                status: 'completed',
                completed_at: Time.current.iso8601
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('completed')
        expect(response_data['data']['completed_at']).to be_present

        termination.reload
        expect(termination.status).to eq('completed')
        expect(termination.completed_at).to be_present
      end

      it "rejects cancelled (not a transition the worker's raw status branch is allowed to make)" do
        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'cancelled' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

        termination.reload
        expect(termination.status).to eq('grace_period')
      end

      # BLOCKER 2 (IMP-b33a3ecca331 third review): the whole-array
      # `termination_log` param is REMOVED entirely (no-legacy rule) —
      # `termination_log_append` is the only way to add entries now, merged
      # server-side onto the current (locked, freshly-reloaded) stored log.
      # Sends the exact raw, job-shaped payload (no nested wrapper).
      it 'appends termination_log entries sent alongside a status update, preserving prior history' do
        termination.update!(
          status: 'processing', processing_started_at: 1.hour.ago,
          termination_log: [ { event: 'processing_started', at: 1.hour.ago.iso8601 } ]
        )

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: {
                status: 'completed',
                completed_at: Time.current.iso8601,
                termination_log_append: [
                  { event: 'deleted_consents', user_id: 'u-1', at: Time.current.iso8601 },
                  { event: 'deleted_files', count: 3, at: Time.current.iso8601 }
                ]
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['termination_log'].size).to eq(3)
        expect(response_data['data']['termination_log'].first).to include('event' => 'processing_started')
        expect(response_data['data']['termination_log'].last).to include('event' => 'deleted_files', 'count' => 3)

        termination.reload
        expect(termination.termination_log.size).to eq(3)
        expect(termination.termination_log.first).to include('event' => 'processing_started')
      end

      # IMP-b33a3ecca331 review follow-up: the first pass of the
      # termination_log permit fix listed event/user_id/count/error/at but
      # missed `reason` — the exact key the job's
      # `subscription_anonymize_skipped` entry carries. Sends that entry
      # verbatim, via termination_log_append.
      it 'appends a termination_log entry carrying a reason key (subscription_anonymize_skipped)' do
        termination.update!(status: 'processing', processing_started_at: 1.hour.ago)

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: {
                status: 'completed',
                completed_at: Time.current.iso8601,
                termination_log_append: [
                  { event: 'subscription_anonymize_skipped', reason: 'no_billing_extension_provider',
                    at: Time.current.iso8601 }
                ]
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['termination_log'].last).to include(
          'event' => 'subscription_anonymize_skipped', 'reason' => 'no_billing_extension_provider'
        )

        termination.reload
        expect(termination.termination_log.last).to include(
          'event' => 'subscription_anonymize_skipped', 'reason' => 'no_billing_extension_provider'
        )
      end

      # BLOCKER 2 (IMP-b33a3ecca331 third review): the whole-array replace
      # this used to be silently stripped keys the MODEL's own writers use
      # (by/days_before/scheduled_for) because they were never in the permit
      # list — and even once permitted, a whole-array replace would still
      # have DISCARDED this entry outright on the next worker write, since
      # the worker never re-sends history it didn't itself fetch verbatim.
      # The append mechanism merges onto whatever is ALREADY stored, so a
      # model-authored entry the worker never even sees survives.
      it 'preserves a model-authored reminder_scheduled entry (days_before/scheduled_for) across an append' do
        # schedule_reminders only seeds entries for FUTURE reminder times —
        # the base `termination` fixture's grace_period_ends_at is already in
        # the past (deliberately, for the processing-transition tests above),
        # so push it into the future here so the 7/3/1-day reminders are
        # actually still ahead of Time.current. schedule_reminders is
        # private — this IS what confirm! calls internally to seed the
        # reminder_scheduled entries this asserts on.
        termination.update_column(:grace_period_ends_at, 10.days.from_now)
        termination.send(:schedule_reminders)
        expect(termination.reload.termination_log).not_to be_empty

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: {
                termination_log_append: [ { event: 'reminder_7_days_sent', at: Time.current.iso8601 } ]
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        termination.reload
        expect(termination.termination_log).to include(
          a_hash_including('event' => 'reminder_scheduled', 'days_before' => 7)
        )
        expect(termination.termination_log.last).to include('event' => 'reminder_7_days_sent')
      end
    end

    context 'when termination does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/account_terminations/nonexistent-id',
              params: { status: 'processing' },
              headers: internal_headers,
              as: :json

        expect_error_response('Account termination not found', 404)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        patch "/api/v1/internal/account_terminations/#{termination.id}",
              params: { status: 'processing' },
              headers: { 'Authorization' => "Bearer #{invalid_token}" },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # SECURITY-RELEVANT (IMP-b33a3ecca331 third review, S-A): mirrors the
  # DataDeletionRequestsController S3 guard spec. Before this fix, this branch
  # let ANY mTLS-enrolled worker principal set ANY valid model status with no
  # audit trail — a worker principal could jump a termination straight to
  # 'completed' (destructive: cancels the account) without ever having gone
  # through 'processing', or restart an un-expired 'grace_period' termination
  # early.
  describe 'PATCH /api/v1/internal/account_terminations/:id status-transition guard' do
    it 'rejects pending -> completed (skipping grace_period and processing entirely)' do
      termination = Account::Termination.create!(
        account: account, status: 'pending', reason: 'user_requested',
        requested_at: Time.current, grace_period_ends_at: 30.days.from_now
      )

      patch "/api/v1/internal/account_terminations/#{termination.id}",
            params: { status: 'completed', completed_at: Time.current.iso8601 },
            headers: internal_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

      termination.reload
      expect(termination.status).to eq('pending')
    end

    it 'rejects grace_period -> processing before the grace period has expired' do
      termination = Account::Termination.create!(
        account: account, status: 'grace_period', reason: 'user_requested',
        requested_at: 2.days.ago, grace_period_ends_at: 5.days.from_now
      )

      patch "/api/v1/internal/account_terminations/#{termination.id}",
            params: { status: 'processing', processing_started_at: Time.current.iso8601 },
            headers: internal_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')

      termination.reload
      expect(termination.status).to eq('grace_period')
    end

    it 'allows grace_period -> processing once expired and writes an account_termination.status_transition audit row' do
      termination = Account::Termination.create!(
        account: account, status: 'grace_period', reason: 'user_requested',
        requested_at: 31.days.ago, grace_period_ends_at: 1.day.ago
      )

      patch "/api/v1/internal/account_terminations/#{termination.id}",
            params: { status: 'processing', processing_started_at: Time.current.iso8601 },
            headers: internal_headers, as: :json

      expect_success_response
      termination.reload
      expect(termination.status).to eq('processing')

      audit_row = AuditLog.find_by(action: 'account_termination.status_transition', resource_id: termination.id)
      expect(audit_row).to be_present
      expect(audit_row.metadata['from_status']).to eq('grace_period')
      expect(audit_row.metadata['to_status']).to eq('processing')
    end

    it 'rejects a status-less log-only write once the termination is completed (history is frozen)' do
      termination = Account::Termination.create!(
        account: account, status: 'completed', reason: 'user_requested',
        requested_at: 40.days.ago, grace_period_ends_at: 10.days.ago, completed_at: 3.days.ago
      )

      # A real job event name (not a forged one) — this test targets the
      # STATUS guard specifically; a forged event name would be rejected by
      # the (unrelated) event-allowlist guard first and never reach it.
      patch "/api/v1/internal/account_terminations/#{termination.id}",
            params: { termination_log_append: [ { event: 'deleted_consents', user_id: 'u-1', at: Time.current.iso8601 } ] },
            headers: internal_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_STATUS_TRANSITION')
    end

    # Fourth review, nit 1: termination_log_append now validates the EVENT
    # NAME itself against the exact set the job builds, not just the entry's
    # keys — `event`/`at` were always permitted keys, so a forged MODEL-only
    # event (e.g. 'confirmed', which only Account::Termination#confirm!
    # writes) would otherwise pass the key filter unchallenged and let a
    # worker principal inject a fabricated model-lifecycle entry into the
    # audit trail.
    it 'rejects a termination_log_append entry with an event name the job never writes' do
      termination = Account::Termination.create!(
        account: account, status: 'processing', reason: 'user_requested',
        requested_at: 31.days.ago, grace_period_ends_at: 1.day.ago, processing_started_at: 1.hour.ago
      )

      patch "/api/v1/internal/account_terminations/#{termination.id}",
            params: { termination_log_append: [ { event: 'confirmed', at: Time.current.iso8601 } ] },
            headers: internal_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['code']).to eq('INVALID_TERMINATION_LOG_EVENT')

      termination.reload
      expect(termination.termination_log.map { |e| e['event'] }).not_to include('confirmed')
    end
  end
end
