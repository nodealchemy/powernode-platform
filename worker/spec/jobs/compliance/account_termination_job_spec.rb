# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::AccountTerminationJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:termination_id) { 'term-123' }
  let(:account_id) { 'account-456' }
  let(:user_id) { 'user-789' }
  let(:job_args) { nil }

  # String-keyed (IMP-b33a3ecca331 third review, BLOCKER 1):
  # BackendApiClient#handle_response returns the Faraday-parsed JSON body
  # VERBATIM on 2xx — string keys, never symbolized, never wrapped in a
  # symbol-keyed {success:, data:} envelope — and raises ApiError on any
  # non-2xx. Every double in this file mirrors that exact shape so a
  # regression back to symbol-key access in the job would actually redden
  # these specs (the previous symbol-keyed doubles could not catch that,
  # because `response[:success]`/`response[:data]` are simply always `nil`
  # against a string-keyed RSpec double too, and `nil` reads as falsy the
  # same way an absent stub would — the job's `return unless response['success']`
  # guard never fired, so no example here ever actually exercised the job's
  # real behavior).
  let(:seeded_reminder_entry) do
    { 'event' => 'reminder_scheduled', 'days_before' => 7,
      'scheduled_for' => 6.days.from_now.iso8601, 'at' => 23.days.ago.iso8601 }
  end

  let(:termination_data) do
    {
      'id' => termination_id,
      'account_id' => account_id,
      'status' => 'grace_period',
      'owner_email' => 'owner@example.com',
      'grace_period_ends_at' => 1.day.ago.iso8601,
      'termination_log' => [ seeded_reminder_entry ]
    }
  end

  let(:users_data) do
    [ { 'id' => user_id, 'email' => 'user@example.com' } ]
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with compliance queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('compliance')
    end
  end

  describe '#execute' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
    end

    context 'when processing ready terminations' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ termination_data ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return('success' => true, 'data' => users_data)
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => termination_data)
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'fetches ready terminations from API' do
        # `.and_return` here is load-bearing, not decorative: a narrower
        # `expect(...).with(...)` on the SAME args as the `before` block's
        # `allow` becomes the match RSpec uses for calls with those args (most
        # recently defined wins) — with no return value it would answer `nil`,
        # and process_ready_terminations' `response['success']` would raise
        # NoMethodError on nil before job.execute below ever got anywhere near
        # what this example claims to check.
        expect(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ termination_data ])

        job.execute
      end

      it 'processes each ready termination' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'processing')
          )
          .and_return('success' => true, 'data' => termination_data)

        job.execute
      end

      it 'deletes user data' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")

        job.execute
      end

      it 'anonymizes audit logs' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})

        job.execute
      end

      it 'deletes account files' do
        # `.and_return` is load-bearing: delete_account_records reads
        # `response['data']&.dig('count')` off THIS call's return value; nil
        # would raise NoMethodError on `nil['data']` (NilClass has no `[]`).
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/files")
          .and_return('success' => true, 'data' => { 'count' => 5 })

        job.execute
      end

      it 'terminates the account via the dedicated idempotent terminate action' do
        # Fork 1 (IMP-b33a3ecca331): marks the account 'cancelled' server-side
        # through Api::V1::Internal::AccountsController#terminate, a narrow
        # no-payload action — not a generic PATCH carrying a status value
        # (there never was a route for that, and 'terminated' was never a
        # value the check constraint allowed).
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/accounts/#{account_id}/terminate", {})
          .and_return('success' => true)

        job.execute
      end

      it 'sends completion notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'account_termination_complete')
          )

        job.execute
      end

      it 'returns results summary' do
        result = job.execute

        expect(result[:processed]).to eq(1)
        expect(result[:errors]).to be_empty
      end

      it 'finalizes a succeeded termination as completed so it is not re-selected' do
        # The re-fetch query filters status: 'grace_period'; a 'completed'
        # termination falls outside that filter and is never re-processed.
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'completed')
          )
          .and_return('success' => true, 'data' => termination_data)

        job.execute
      end

      it 'never reverts a succeeded termination back to grace_period' do
        # A succeeded account must NOT be made re-selectable (no double-termination).
        expect(api_client).not_to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'grace_period')
          )

        job.execute
      end

      # (a) IMP-b33a3ecca331 third review, BLOCKER 1 new example: terminate
      # PATCHed before the 'completed' PATCH (S1). Would redden on revert to
      # the pre-S1 ordering (terminate_account! called AFTER the 'completed'
      # write): a failure between the two would then leave the termination
      # record permanently 'completed' (outside every re-fetch filter, so
      # never retried) while the account itself was never actually
      # cancelled — an unrecoverable inconsistent state.
      it 'PATCHes terminate before the completed status write, in that order' do
        call_order = []
        allow(api_client).to receive(:patch) do |path, payload|
          call_order << :terminate if path == "/api/v1/internal/accounts/#{account_id}/terminate"
          call_order << :completed if path.include?('account_terminations') && payload[:status] == 'completed'
          { 'success' => true, 'data' => termination_data }
        end

        job.execute

        expect(call_order).to eq([ :terminate, :completed ])
      end

      # (b) IMP-b33a3ecca331 third review, BLOCKER 1 new example: the append
      # mechanism (BLOCKER 2) sends only this run's NEW log entries, not the
      # seeded/fetched history — the server now merges them onto the stored
      # log itself (AccountTerminationsController#update,
      # termination_log_append). Would redden on a revert to sending the
      # whole accumulated array back (the prior, second-round fix): that
      # payload would carry `seeded_reminder_entry` a second time instead of
      # omitting it, and this example asserts it is ABSENT from the
      # completed-status payload.
      it 'sends only new termination_log entries on the completed write, not the seeded history' do
        # `allow` (not `expect`), and the payload captured for a post-hoc
        # assertion rather than checked inside the stub block: `patch` is
        # called several times per run (processing/anonymize/terminate/
        # completed), and an `expect(...).to receive` here would need an
        # explicit call-count qualifier just to tolerate that — easy to get
        # the block/qualifier precedence wrong (a `do...end` after a chained
        # qualifier binds to `.to`, not to `receive`, silently discarding the
        # implementation). `allow` has no such cardinality expectation.
        completed_payload = nil
        allow(api_client).to receive(:patch) do |path, payload|
          if path == "/api/v1/internal/account_terminations/#{termination_id}" && payload[:status] == 'completed'
            completed_payload = payload
          end
          { 'success' => true, 'data' => termination_data }
        end

        job.execute

        expect(completed_payload).not_to be_nil
        expect(completed_payload[:termination_log_append]).not_to include(seeded_reminder_entry)
        expect(completed_payload).not_to have_key(:termination_log)
      end
    end

    context 'when no terminations are ready' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
      end

      it 'completes without processing' do
        result = job.execute

        expect(result[:processed]).to eq(0)
      end
    end

    context 'when sending termination reminders' do
      let(:reminder_termination) do
        termination_data.merge('grace_period_ends_at' => 7.days.from_now.iso8601)
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [ reminder_termination ])
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => reminder_termination)
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'sends 7-day reminder notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'account_termination_reminder')
          )

        job.execute
      end

      it 'updates termination log with only the new reminder-sent entry' do
        # termination_log_append (BLOCKER 2), not the whole-array replace this
        # used to send — and NOT the seeded reminder_scheduled entry already
        # on the fetched record, which the server already has.
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(termination_log_append: [ hash_including(event: 'reminder_7_days_sent') ])
          )
          .and_return('success' => true, 'data' => reminder_termination)

        job.execute
      end

      it 'returns reminders sent count' do
        result = job.execute

        expect(result[:reminders_sent]).to eq(1)
      end
    end

    context 'when termination processing fails' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ termination_data ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return('success' => true, 'data' => users_data)
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => termination_data)
        allow(api_client).to receive(:post).and_return('success' => true)
        # Data deletion fails AFTER the account was marked 'processing' (the
        # exact scenario that previously stranded the account in 'processing').
        allow(api_client).to receive(:delete)
          .and_raise(StandardError, 'API error')
      end

      it 'logs the per-account failure' do
        expect(job).to receive(:log_error).with(/Failed to process termination/)

        expect { job.execute }.to raise_error(StandardError)
      end

      it 'fails loud so Sidekiq retries instead of reporting a false success' do
        # Previously the job swallowed the failure into results[:errors] and
        # returned normally, so Sidekiq saw success and retry:3 never fired.
        expect { job.execute }.to raise_error(/Account termination failed/)
      end

      it 'reverts the failed termination to grace_period so it is re-selectable' do
        # grace_period matches the re-fetch filter
        # (status: 'grace_period', grace_period_expired: true), so the next run
        # re-attempts it instead of stranding it forever in 'processing'.
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'grace_period')
          )

        expect { job.execute }.to raise_error(StandardError)
      end

      # (c) IMP-b33a3ecca331 third review, BLOCKER 1 new example: the ORIGINAL
      # error is re-raised even when the rescue's own grace_period-revert
      # write also raises. Exercises #process_termination directly (not
      # #execute): #execute's own outer wrapping (process_ready_terminations
      # catches every per-item error into results[:errors], and #execute then
      # raises ITS OWN "Account termination failed for: ..." summary message)
      # would mask which underlying message survived either way, at the
      # `execute`-level — the property under test lives one level down, in
      # #process_termination's nested rescue, so assert there directly. Would
      # redden on a revert to a bare (non-nested) `patch_termination!` call in
      # the rescue: the write's own exception ("Failed to update account
      # termination...") would replace `e` on the implicit re-raise, so
      # #process_termination would raise THAT message instead of the original
      # "API error" domain failure — losing it entirely.
      context 'and the grace_period-revert write also fails' do
        before do
          allow(api_client).to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", hash_including(status: 'grace_period'))
            .and_return('success' => false, 'error' => 'write conflict')
        end

        it 're-raises the original processing error, not the revert-write failure' do
          expect { job.send(:process_termination, termination_data) }.to raise_error(/API error/)
        end

        it 'logs the revert-write failure without swallowing it silently' do
          expect(job).to receive(:log_error).with(/Failed to revert termination .* to grace_period/)

          expect { job.send(:process_termination, termination_data) }.to raise_error(StandardError)
        end
      end
    end
  end
end
