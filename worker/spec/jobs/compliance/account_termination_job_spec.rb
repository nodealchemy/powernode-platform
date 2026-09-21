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
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
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
        # A fresh grace_period termination is not a resumed strand.
        expect(result[:resumed]).to eq(0)
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

    # IMP-f0560910fa62: process_termination PATCHes status: 'processing'
    # BEFORE entering its begin/rescue (line ~78). If the worker dies in that
    # window -- or anywhere before the completed/grace_period write lands --
    # the rescue never runs and the row is stranded: process_ready_terminations
    # only ever asks for {status: 'grace_period', grace_period_expired: true},
    # and no other query re-selects 'processing'.
    #
    # This does NOT simply mirror DataDeletionJob (IMP-b33a3ecca331) treating
    # any 'processing' row as safe to resume: that precedent is per-id,
    # re-invoked only by Sidekiq's OWN retry, which guarantees the prior
    # attempt is dead. This job is a periodic SWEEP with no such guarantee --
    # a 'processing' row could be a crash (safe to resume) or a run still
    # genuinely in flight (resuming would double-process a live termination).
    # Status alone can't distinguish them, so the fix filters on
    # processing_started_at (written atomically with the status, :80):
    # only a row idle longer than STRANDED_PROCESSING_THRESHOLD is stranded.
    context 'when a termination is in processing' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [])
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

      context 'and it has been idle past the staleness threshold (a prior crash)' do
        let(:stranded_termination) do
          termination_data.merge('status' => 'processing', 'processing_started_at' => 7.hours.ago.iso8601)
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ stranded_termination ])

          # BLOCKER 1 (IMP-f0560910fa62 review): the server's own guard
          # (account_terminations_controller.rb#status_transition_allowed?)
          # permits ONLY processing -> {completed, grace_period}, never
          # processing -> processing -- so re-issuing the SAME initial
          # status write this job sends for a fresh grace_period row would
          # 422 against a row that is ALREADY 'processing'. Modeling that
          # here (rather than a blanket success stub for every patch) is
          # what makes this context able to catch a regression back to the
          # unconditional write: a blanket `.and_return('success' => true)`
          # stub can't distinguish a real invalid-transition 422 from a
          # valid one, which is exactly how the original unit tests missed
          # this -- they never talked to the real server's guard.
          allow(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/account_terminations/#{termination_id}",
              hash_including(status: 'processing')
            )
            .and_raise(BackendApiClient::ApiError, "422: Invalid status transition from 'processing' to 'processing'")
        end

        it 'does not re-issue the initial processing status write on a resumed row' do
          expect(api_client).not_to receive(:patch)
            .with(
              "/api/v1/internal/account_terminations/#{termination_id}",
              hash_including(status: 'processing')
            )

          job.execute
        end

        it 'resumes and completes it rather than leaving it forever unreachable' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/account_terminations/#{termination_id}",
              hash_including(status: 'completed')
            )
            .and_return('success' => true, 'data' => stranded_termination)

          job.execute
        end

        it 'counts it as processed' do
          result = job.execute

          expect(result[:processed]).to eq(1)
        end

        # Cosmetic (IMP-f0560910fa62 review, finding 5): resumed is a
        # SUBSET of processed, tracked separately so an operator can see a
        # strand occurred without grepping logs.
        it 'counts it as a resumed strand, not just a newly-processed termination' do
          result = job.execute

          expect(result[:resumed]).to eq(1)
        end

        it 'does not raise or strand the row on the redundant write the server would 422 on' do
          expect { job.execute }.not_to raise_error
        end
      end

      # Brackets the THRESHOLD VALUE (IMP-f0560910fa62 review, finding 1):
      # 3 hours is stale under the fix's ORIGINAL 1-hour value but still
      # within the CURRENT 6-hour one. This constrains the value to
      # 3h <= T < 7h against this file's other two fixtures (7h, 5min) --
      # it is a bracket, not an exact pin (a 6h -> 4h regression would still
      # pass; exact pinning would need 5h59m/6h01m fixtures, which is
      # brittle, and asserting the constant against itself proves nothing).
      # Still valuable: without it, a regression back to 1 hour (or anything
      # below 3h) would silently pass every other example in this file --
      # "idle past threshold" (7h) and "started recently" (5min) are both
      # unaffected by 1h-vs-6h and can't distinguish the two values.
      context 'and it is idle for 3 hours (stale under the fix\'s original 1-hour value, not under the current 6-hour one)' do
        let(:borderline_termination) do
          termination_data.merge('status' => 'processing', 'processing_started_at' => 3.hours.ago.iso8601)
        end

        before do
          # `expect` (not `allow`): this context has no log_error assertion
          # to self-pin on (correctly -- a young row logs nothing), and it is
          # the ONLY example bracketing the threshold from below, so an
          # `allow` here would leave it green even if the whole
          # stranded-processing feature (the `+ stranded_processing_terminations`
          # concatenation) were deleted -- nothing would call patch/delete
          # either way, and `processed == 0` would pass vacuously. Matches
          # the same fix already applied to "started recently", below.
          expect(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ borderline_termination ])
        end

        it 'does not touch it -- a live run this size can still be in flight' do
          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'does not count it as processed' do
          result = job.execute

          expect(result[:processed]).to eq(0)
        end
      end

      # The negative arm a staleness gate needs to be able to fail
      # differently: without it, a gate that always resumes (or one whose
      # threshold is wired to the wrong field/comparison) is indistinguishable
      # from a correct one -- only this example can tell them apart.
      context 'and it started recently (a run genuinely still in flight)' do
        let(:recent_termination) do
          termination_data.merge('status' => 'processing', 'processing_started_at' => 5.minutes.ago.iso8601)
        end

        before do
          # `expect` (not `allow`): pins that the stranded-row fetch is
          # actually MADE. An `allow` here would leave this example green
          # even if the whole stranded-processing feature were removed --
          # nothing would call patch/delete either way, and "does not count
          # it as processed" would pass vacuously too.
          expect(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ recent_termination ])
        end

        it 'does not touch it -- a concurrent run may still own it' do
          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'does not count it as processed' do
          result = job.execute

          expect(result[:processed]).to eq(0)
        end
      end

      # DESIGN DECISION (IMP-f0560910fa62 review, changed from the original
      # fix): an undeterminable age -- absent, blank, or unparseable -- is
      # now QUARANTINED (skipped, not counted, logged at error), not
      # resumed. The original version of this fix resumed unconditionally
      # here, reasoning that a missing processing_started_at could only mean
      # process_termination's own write invariant broke. That premise was
      # disproven by the SAME review: the server's index serializer
      # (termination_data) never included this field at all, so every
      # 'processing' row arrived absent on a perfectly healthy system -- the
      # staleness gate was silently inert, resuming every row regardless of
      # true age. "I cannot determine this row's state, therefore I will act
      # on it" is the wrong default on a path that anonymizes users and
      # cancels accounts. Quarantining leaves the row exactly as stuck as it
      # already was (no regression), while surfacing it to an operator.
      #
      # Fixture note: omits the key entirely (`termination_data.merge('status'
      # => 'processing')`) rather than setting it to an explicit `nil` --
      # that is the REAL payload shape a Hash#[] lookup on a JSON body
      # produces when a field is absent, and it survives a later rewrite of
      # the guard to `key?`/`fetch`.
      context 'and processing_started_at is absent (the exact shape the missing serializer field produced)' do
        let(:anomalous_termination) do
          termination_data.merge('status' => 'processing')
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ anomalous_termination ])
        end

        it 'does not resume it -- quarantines it instead of acting on an undeterminable row' do
          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'does not count it as processed' do
          result = job.execute

          expect(result[:processed]).to eq(0)
        end

        # `/processing_started_at/` alone would match BOTH this message and
        # the unparseable-garbage message below -- `/should never happen/`
        # is unique to this (blank/absent) branch, so it actually
        # discriminates between the two log call sites.
        it 'logs the anomaly at error severity so it surfaces to an operator' do
          expect(job).to receive(:log_error).with(/should never happen/)

          job.execute
        end
      end

      # A non-blank but structurally invalid processing_started_at reaches
      # parse_processing_started_at by a different path than the absent case
      # above: Time.zone.parse either raises (ArgumentError/TypeError,
      # rescued) or returns nil, and both land in unparseable_processing_started_at!
      # -- same quarantine outcome, but a distinct code path worth its own
      # example. stranded_processing_terminations runs OUTSIDE
      # process_ready_terminations' per-item rescue (it BUILDS the array that
      # method's each iterates), and #execute has no rescue around
      # process_ready_terminations itself -- only send_termination_reminders
      # follows it, unguarded. A raise here would abort the whole sweep before
      # any per-item bookkeeping exists, skip send_termination_reminders
      # entirely, and bypass the fail-loud/revert-to-grace_period mechanism at
      # the end of #execute; unlike a per-item failure, Sidekiq's retry: 3
      # would then re-run the WHOLE job against the SAME bad row every time.
      # One malformed row must not take the entire sweep down with it -- the
      # ordinary grace_period termination in the same sweep (below) is what
      # actually pins that blast radius, not just that the parse doesn't raise.
      context 'and processing_started_at is unparseable garbage' do
        let(:unparseable_termination) do
          # A structurally invalid date (the code's own comment names this
          # exact string) -- Time.zone.parse RAISES ArgumentError for this
          # shape, unlike a merely-nonsensical string such as "garbage" or
          # "not-a-timestamp", both of which it returns nil for without
          # raising. This example needs the raising shape to actually
          # exercise parse_processing_started_at's `rescue ArgumentError,
          # TypeError` arm (confirmed by direct execution: Time.zone.parse
          # returns nil, not a raise, for "not-a-timestamp").
          termination_data.merge('status' => 'processing', 'processing_started_at' => '2026-99-99')
        end

        let(:other_account_id) { 'account-999' }
        let(:other_termination_id) { 'term-999' }
        let(:other_termination_data) do
          termination_data.merge('id' => other_termination_id, 'account_id' => other_account_id,
                                  'status' => 'grace_period')
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ other_termination_data ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ unparseable_termination ])
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/accounts/#{other_account_id}/users")
            .and_return('success' => true, 'data' => users_data)
        end

        it 'does not raise, and quarantines the unparseable row without resuming it' do
          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)

          expect { job.execute }.not_to raise_error
        end

        it 'still processes the normal grace_period termination in the same sweep' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/account_terminations/#{other_termination_id}",
              hash_including(status: 'completed')
            )
            .and_return('success' => true, 'data' => other_termination_data)

          job.execute
        end

        it 'counts only the normal termination as processed, not the quarantined one' do
          result = job.execute

          expect(result[:processed]).to eq(1)
        end

        it 'logs the anomaly at error severity so it surfaces to an operator' do
          expect(job).to receive(:log_error).with(/unparseable processing_started_at/)

          job.execute
        end
      end

      # A future-dated processing_started_at PARSES CLEANLY (confirmed by
      # direct execution: Time.zone.parse("999999999999-01-01") raises
      # nothing), so it escapes both the blank and unparseable branches above
      # (IMP-f0560910fa62 review, finding 4). Left unhandled, the age
      # comparison in stranded_processing_terminations would simply evaluate
      # false -- silently treating it as "not yet stale" with no anomaly ever
      # logged, which is worse than either other anomaly: those at least
      # surface via an error log even though they're also not resumed. This
      # case must not be indistinguishable from an ordinary young row.
      context 'and processing_started_at is in the future (clock skew or corrupted data)' do
        let(:future_termination) do
          termination_data.merge('status' => 'processing', 'processing_started_at' => '999999999999-01-01')
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ future_termination ])
        end

        it 'does not resume it -- quarantines it instead of treating it as merely young' do
          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'does not count it as processed' do
          result = job.execute

          expect(result[:processed]).to eq(0)
        end

        # `/in the future/` is unique to this branch -- distinct from
        # `/should never happen/` (blank) and `/unparseable processing_started_at/`
        # (garbage), so this actually discriminates the three log call sites.
        it 'logs the anomaly at error severity so it surfaces to an operator' do
          expect(job).to receive(:log_error).with(/in the future/)

          job.execute
        end
      end
    end

    # DEDUPE (IMP-f0560910fa62 review, finding 3): status being a single
    # column makes process_ready_terminations' two queries' filters disjoint
    # only in ONE instantaneous snapshot -- they are two SEQUENTIAL HTTP
    # requests, so a row that was 'grace_period'+expired when the first ran
    # can have moved to 'processing' by the time the second ran a moment
    # later (an overlapping sweep, a Sidekiq retry racing the cron, or an
    # admin action), landing in BOTH arrays. Without de-duplication this
    # would call process_termination for the SAME row twice in one loop: the
    # second call would find it already 'processing' from the first call's
    # own write and hit the exact 422 BLOCKER 1 exists to avoid.
    context 'when a termination appears in both the ready and stranded queries (a race)' do
      let(:racing_termination_as_ready) do
        termination_data.merge('status' => 'grace_period')
      end

      let(:racing_termination_as_stranded) do
        termination_data.merge('status' => 'processing', 'processing_started_at' => 7.hours.ago.iso8601)
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ racing_termination_as_ready ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [ racing_termination_as_stranded ])
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return('success' => true, 'data' => users_data)
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => termination_data)
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'processes the colliding row exactly once, not twice' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'completed')
          )
          .once
          .and_return('success' => true, 'data' => termination_data)

        result = job.execute

        expect(result[:processed]).to eq(1)
      end

      # Array#uniq keeps the FIRST occurrence, and stranded_terminations is
      # concatenated first in process_ready_terminations specifically so the
      # MORE CURRENT (chronologically later-fetched) copy wins a collision --
      # here, the 'processing' copy, which is treated as a resume rather than
      # a fresh grace_period -> processing transition.
      it 'treats the collision as a resume (the more-current, stranded copy wins), not a fresh transition' do
        expect(api_client).not_to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'processing')
          )

        result = job.execute

        expect(result[:resumed]).to eq(1)
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
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
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
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [])
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
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
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
