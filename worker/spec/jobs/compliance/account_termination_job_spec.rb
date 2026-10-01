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

      # The completion notice address is read from the internal SHOW, never the
      # list (IMP-b719328ddeb9): the owner is already anonymized by the time the
      # termination completes, so the address is the snapshot taken at request time.
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/account_terminations/#{termination_id}")
        .and_return('success' => true, 'data' => { 'id' => termination_id,
                                                   'notification_email' => 'snapshot@example.com' })
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
        # `response['data']` off THIS call's return value; nil would raise
        # NoMethodError on `nil['data']` (NilClass has no `[]`).
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/files")
          .and_return('success' => true, 'data' => { 'count' => 5 })

        job.execute
      end

      # IMP-bf52b4da135b — the files endpoint has never actually erased
      # anything and now says so (`erased: false`). The termination_log must
      # carry that as an UNMET obligation, not as a `deleted_files` entry
      # reporting a deletion that did not happen: an operator reading this
      # log has to be able to see that files survived.
      context 'when the server reports that files were not erased' do
        before do
          allow(api_client).to receive(:delete)
            .with("/api/v1/internal/accounts/#{account_id}/files")
            .and_return(
              'success' => true,
              'data' => { 'count' => 0, 'erased' => false, 'reason' => 'no_erasure_path' }
            )
        end

        it 'records the skip with its reason, rather than a deletion' do
          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true }
          end

          job.execute

          expect(appended).to include(
            hash_including(event: 'files_erasure_skipped', reason: 'no_erasure_path')
          )
        end

        it 'writes no deleted_files entry for an erasure that did not happen' do
          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true }
          end

          job.execute

          expect(appended.map { |e| e[:event] }).to include('files_erasure_skipped')
          expect(appended.map { |e| e[:event] }).not_to include('deleted_files')
        end
      end

      it 'still records a real deletion when the server reports one (legacy//implemented path)' do
        # Guards the `erased == false` check against becoming a truthiness
        # test: an older server build returns neither `erased` nor `reason`,
        # and must still be treated as the deletion path.
        appended = []
        allow(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/files")
          .and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:patch) do |_path, payload|
          appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
          { 'success' => true }
        end

        job.execute

        expect(appended).to include(hash_including(event: 'deleted_files', count: 5))
        expect(appended.map { |e| e[:event] }).not_to include('files_erasure_skipped')
      end

      # IMP-d97f6e3bbc2b — the files endpoint is a real, bounded erasure now:
      # one batch per request with a cursor, `failed` naming every file it
      # could not erase with a kind. A HELD file (a referent will not let
      # go — a boot image, say) is a policy gap no retry clears: recorded in
      # the termination_log and the termination proceeds. An ERROR (the
      # provider did not remove a blob) is operational: the termination
      # reverts to grace_period and the next sweep retries, like every other
      # failed step here. Neither is ever a silent success.
      context 'with the batched files erasure' do
        let(:files_path) { "/api/v1/internal/accounts/#{account_id}/files" }
        # Real-shaped cursors: the server rejects anything but a UUID with 422.
        let(:cursor_1) { SecureRandom.uuid }
        let(:cursor_2) { SecureRandom.uuid }

        def files_batch(count:, remaining:, cursor:, failed: [])
          {
            'success' => true,
            'data' => {
              'count' => count, 'erased' => true, 'failed' => failed,
              'remaining' => remaining, 'cursor' => cursor, 'retained_platform_artifacts' => 1
            }
          }
        end

        def appended_entries
          appended = []
          allow(api_client).to receive(:patch) do |path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => termination_data }
          end
          appended
        end

        it 'walks the cursor until nothing remains and records the summed count' do
          expect(api_client).to receive(:delete).with(files_path).ordered
            .and_return(files_batch(count: 2, remaining: 1, cursor: cursor_1))
          expect(api_client).to receive(:delete).with(files_path, { after_id: cursor_1 }).ordered
            .and_return(files_batch(count: 1, remaining: 0, cursor: cursor_2))
          appended = appended_entries

          job.execute

          expect(appended).to include(hash_including(event: 'deleted_files', count: 3))
        end

        it 'records held files as a gap in the termination_log and still completes the termination' do
          allow(api_client).to receive(:delete).with(files_path).and_return(
            files_batch(count: 4, remaining: 0, cursor: cursor_1,
                        failed: [ { 'id' => 'file-9', 'kind' => 'held', 'reason' => 'held_by_boot_image' } ])
          )
          appended = appended_entries

          job.execute

          expect(appended).to include(hash_including(event: 'deleted_files', count: 4))
          expect(appended).to include(
            hash_including(event: 'files_erasure_held', count: 1,
                           files: [ { id: 'file-9', reason: 'held_by_boot_image' } ])
          )
          expect(appended.map { |e| e[:event] }).to include('deleted_api_keys')
        end

        it 'stops walking after a batch in which every file failed operationally — the provider is down' do
          allow(api_client).to receive(:delete).with(files_path).and_return(
            files_batch(count: 0, remaining: 5, cursor: cursor_1,
                        failed: [ { 'id' => 'file-1', 'kind' => 'error', 'reason' => 'storage_removal_failed' },
                                  { 'id' => 'file-2', 'kind' => 'error', 'reason' => 'storage_removal_failed' } ])
          )
          appended = appended_entries

          expect { job.execute }.to raise_error(/Account termination failed for: #{termination_id}/)

          expect(api_client).to have_received(:delete).with(files_path).once
          expect(api_client).not_to have_received(:delete).with(files_path, anything)
          expect(appended).to include(hash_including(event: 'error', error: /5 remaining/))
        end

        it 'stops a cursor that never finishes instead of looping forever' do
          stub_const('ComplianceFileErasureConcern::MAX_FILE_ERASURE_BATCHES', 3)
          allow(api_client).to receive(:delete).with(files_path)
            .and_return(files_batch(count: 1, remaining: 1, cursor: cursor_1))
          allow(api_client).to receive(:delete).with(files_path, hash_including(:after_id)) do |_path, params|
            files_batch(count: 1, remaining: 1, cursor: SecureRandom.uuid)
          end
          appended = appended_entries

          expect { job.execute }.to raise_error(/Account termination failed for: #{termination_id}/)

          expect(api_client).to have_received(:delete).with(files_path, anything).exactly(2).times
          expect(appended).to include(hash_including(event: 'error', error: /did not finish within 3 batches/))
        end

        it 'reverts the termination and fails loud when a blob could not be removed' do
          allow(api_client).to receive(:delete).with(files_path).and_return(
            files_batch(count: 1, remaining: 0, cursor: cursor_1,
                        failed: [ { 'id' => 'file-2', 'kind' => 'error', 'reason' => 'storage_removal_failed' } ])
          )
          appended = appended_entries

          expect { job.execute }.to raise_error(/Account termination failed for: #{termination_id}/)

          expect(appended).to include(hash_including(event: 'error', error: /storage_removal_failed/))
          expect(appended.map { |e| e[:event] }).not_to include('deleted_api_keys')
          expect(api_client).to have_received(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", hash_including(status: 'grace_period'))
        end
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

      it 'addresses the completion notification to the snapshot read from the show endpoint' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'account_termination_complete', email: 'snapshot@example.com')
          )

        job.execute
      end

      it 'reads the snapshot before the completing write, which scrubs it server-side' do
        order = []
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/account_terminations/#{termination_id}") do
          order << :read_snapshot
          { 'success' => true, 'data' => { 'notification_email' => 'snapshot@example.com' } }
        end
        allow(api_client).to receive(:patch) do |path, payload|
          order << :complete if path.end_with?(termination_id) && payload[:status] == 'completed'
          { 'success' => true, 'data' => termination_data }
        end

        job.execute

        expect(order).to eq(%i[read_snapshot complete])
      end

      it 'never writes the snapshotted address to the log' do
        job.execute

        %i[log_info log_error log_warn].each do |logger|
          expect(job).not_to have_received(logger).with(/snapshot@example\.com/)
        end
      end

      context 'when the snapshot is absent (a legacy row)' do
        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/account_terminations/#{termination_id}")
            .and_return('success' => true, 'data' => { 'id' => termination_id, 'notification_email' => nil })
        end

        it 'sends nothing to a nil address, warns, and still completes the termination' do
          expect(api_client).not_to receive(:post)
            .with('/api/v1/internal/notifications/send', hash_including(type: 'account_termination_complete'))
          expect(api_client).to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", hash_including(status: 'completed'))
            .and_return('success' => true, 'data' => termination_data)

          result = job.execute

          expect(result[:errors]).to be_empty
          expect(job).to have_received(:log_warn).with(/no notification address/i)
        end
      end

      context 'when reading the snapshot fails' do
        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/account_terminations/#{termination_id}")
            .and_raise(StandardError, 'read timeout')
        end

        it 'warns and still completes the termination rather than failing it' do
          expect(api_client).not_to receive(:post)
            .with('/api/v1/internal/notifications/send', hash_including(type: 'account_termination_complete'))
          expect(api_client).to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", hash_including(status: 'completed'))
            .and_return('success' => true, 'data' => termination_data)

          result = job.execute

          expect(result[:errors]).to be_empty
          expect(job).to have_received(:log_warn).with(/no notification address/i)
        end
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

    # IMP-0310a1351dab: account_terminations.data_export_request_id (set by
    # Account::Termination.initiate whenever request_data_export: true is
    # honoured) references DataManagement::ExportRequest with no on_delete —
    # deleting a still-pending/processing export's row from underneath that
    # FK would raise ActiveRecord::InvalidForeignKey server-side, and did so
    # on EVERY sweep, forever (the row was never actually removed, so the
    # next sweep hit the identical crash). An export-requesting termination
    # must still be able to complete: it defers here instead, rather than
    # crashing, and is re-checked next sweep — completing once the export
    # (Compliance::DataExportJob, queued by Account::Termination.initiate)
    # reaches a terminal state.
    context 'when the termination requested a data export that has not yet been delivered' do
      let(:pending_export_termination) { termination_data.merge('data_export_request_id' => 'export-1') }

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ pending_export_termination ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_export_requests/export-1')
          .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-1', 'status' => 'pending', 'delivered_for_deletion' => false } })
        # A fresh 'grace_period' row's deferral now always writes a
        # log-only append (IMP-0310a1351dab review round 2, item 4) — this
        # context has its own dedicated examples on that below, this stub is
        # just so the OTHER examples in this context (which assert what does
        # NOT happen) don't blow up on an unstubbed instance_double call.
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => pending_export_termination)
      end

      it 'does not begin deleting any account data' do
        expect(api_client).not_to receive(:delete)

        job.execute
      end

      it 'does not mark the termination processing (leaves it re-checkable next sweep)' do
        expect(api_client).not_to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'processing')
          )

        job.execute
      end

      it 'does not terminate (cancel) the account' do
        expect(api_client).not_to receive(:patch)
          .with("/api/v1/internal/accounts/#{account_id}/terminate", {})

        job.execute
      end

      # A deferred termination is neither a processed success nor a raised
      # error (see the "when a termination requested a data export that has
      # completed" example below for the positive case that DOES count).
      it 'does not count as a processing error' do
        result = job.execute

        expect(result[:errors]).to be_empty
      end

      # IMP-0310a1351dab review round 2, item 4: process_termination now
      # returns :deferred and process_ready_terminations must not count that
      # as processed work.
      it 'does not count as processed (a deferral is not processed work)' do
        result = job.execute

        expect(result[:processed]).to eq(0)
      end

      # The OLD version only appended 'export_pending_deferred' when
      # reverting a resumed-stranded 'processing' row — a fresh 'grace_period'
      # row (the common case, and this context's own fixture) got no record
      # of ever being deferred, so EXPORT_STALL_WARNING_DEFERRAL_COUNT could
      # never be reached for it.
      it 'records the deferral in the termination log even though it never left grace_period' do
        appended = []
        allow(api_client).to receive(:patch) do |_path, payload|
          appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
          { 'success' => true, 'data' => pending_export_termination }
        end

        job.execute

        expect(appended).to include(hash_including(event: 'export_pending_deferred'))
      end

      context 'and the export has been pending longer than the stale threshold' do
        let(:stale_pending_export_termination) { termination_data.merge('data_export_request_id' => 'export-1a') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ stale_pending_export_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-1a')
            .and_return(
              'success' => true,
              'data' => {
                'data_export_request' => {
                  'id' => 'export-1a', 'status' => 'pending', 'delivered_for_deletion' => false,
                  'created_at' => (Compliance::AccountTerminationJob::EXPORT_STALE_PENDING_THRESHOLD + 1.minute).ago.iso8601
                }
              }
            )
        end

        it 're-queues Compliance::DataExportJob for the stale export' do
          expect(Compliance::DataExportJob).to receive(:perform_async).with('export-1a')

          job.execute
        end
      end

      context 'and the export is still young (within the stale threshold)' do
        let(:young_pending_export_termination) { termination_data.merge('data_export_request_id' => 'export-1b') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ young_pending_export_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-1b')
            .and_return(
              'success' => true,
              'data' => {
                'data_export_request' => {
                  'id' => 'export-1b', 'status' => 'pending', 'delivered_for_deletion' => false,
                  'created_at' => 5.minutes.ago.iso8601
                }
              }
            )
        end

        it 'does not re-queue a young, still-plausibly-in-flight export' do
          expect(Compliance::DataExportJob).not_to receive(:perform_async)

          job.execute
        end
      end

      # Review round 3, item 4: a 'processing' export stuck past
      # EXPORT_STALE_PROCESSING_THRESHOLD is treated as failed and routed
      # through the SAME bounded retry as an explicit failure — without
      # this it would sit 'processing' forever (only a still-'pending' row
      # is covered by the stale-pending requeue above).
      context "and the export has been 'processing' longer than the stale-processing threshold" do
        let(:stale_processing_termination) { termination_data.merge('data_export_request_id' => 'export-1c') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ stale_processing_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-1c')
            .and_return(
              'success' => true,
              'data' => {
                'data_export_request' => {
                  'id' => 'export-1c', 'status' => 'processing', 'delivered_for_deletion' => false,
                  'metadata' => {},
                  'processing_started_at' => (Compliance::AccountTerminationJob::EXPORT_STALE_PROCESSING_THRESHOLD + 1.minute).ago.iso8601
                }
              }
            )
          allow(api_client).to receive(:patch).and_return('success' => true, 'data' => stale_processing_termination)
        end

        it "marks the export failed via action_type: fail before retrying it" do
          expect(api_client).to receive(:patch)
            .with('/api/v1/internal/data_export_requests/export-1c', hash_including(action_type: 'fail'))
            .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-1c' } })

          job.execute
        end

        it 'resets it to pending and re-queues Compliance::DataExportJob, same as an explicit failure' do
          expect(Compliance::DataExportJob).to receive(:perform_async).with('export-1c')

          job.execute
        end

        it 'does not proceed with deleting account data' do
          expect(api_client).not_to receive(:delete)

          job.execute
        end
      end

      context "and the export's 'processing' age is still within the stale-processing threshold" do
        let(:fresh_processing_termination) { termination_data.merge('data_export_request_id' => 'export-1d') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ fresh_processing_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-1d')
            .and_return(
              'success' => true,
              'data' => {
                'data_export_request' => {
                  'id' => 'export-1d', 'status' => 'processing', 'delivered_for_deletion' => false,
                  'processing_started_at' => 10.minutes.ago.iso8601
                }
              }
            )
          allow(api_client).to receive(:patch).and_return('success' => true, 'data' => fresh_processing_termination)
        end

        it 'does not mark a still-plausibly-running export as failed' do
          expect(api_client).not_to receive(:patch)
            .with('/api/v1/internal/data_export_requests/export-1d', hash_including(action_type: 'fail'))

          job.execute
        end
      end

      context 'and it has already been deferred EXPORT_STALL_WARNING_DEFERRAL_COUNT - 1 times before' do
        let(:already_deferred_twice) do
          pending_export_termination.merge(
            'termination_log' => [
              seeded_reminder_entry,
              { 'event' => 'export_pending_deferred', 'at' => 2.days.ago.iso8601 },
              { 'event' => 'export_pending_deferred', 'at' => 1.day.ago.iso8601 }
            ]
          )
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ already_deferred_twice ])
        end

        it 'writes a once-only export_stalled_warning log entry and logs a warning' do
          expect(job).to receive(:log_warn).with(/deferred 3 times/)

          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => already_deferred_twice }
          end

          job.execute

          expect(appended).to include(hash_including(event: 'export_stalled_warning'))
        end

        it 'does not write a second export_stalled_warning once one already exists' do
          already_warned = already_deferred_twice.merge(
            'termination_log' => already_deferred_twice['termination_log'] + [
              { 'event' => 'export_stalled_warning', 'at' => 12.hours.ago.iso8601 }
            ]
          )
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ already_warned ])

          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => already_warned }
          end

          job.execute

          expect(appended).not_to include(hash_including(event: 'export_stalled_warning'))
        end

        # Review round 3, item 4: bound termination_log growth. Once the
        # stall warning has already fired, no FURTHER 'export_pending_deferred'
        # entry should be written either — the account_terminations PATCH
        # call for this bookkeeping must not happen at all, or the log grows
        # by one entry every single sweep for as long as the export stays
        # stuck (which, absent a resolution, is unbounded).
        it 'stops appending export_pending_deferred entirely once already warned' do
          already_warned = already_deferred_twice.merge(
            'termination_log' => already_deferred_twice['termination_log'] + [
              { 'event' => 'export_stalled_warning', 'at' => 12.hours.ago.iso8601 }
            ]
          )
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ already_warned ])

          expect(api_client).not_to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", anything)

          job.execute
        end
      end
    end

    # Operator ruling 2026-09-24: delivered = downloaded, or download window
    # elapsed unused. The server computes this into `delivered_for_deletion`
    # (see DataManagement::ExportRequest#delivered_for_deletion?) — this job
    # only ever reads that one field, so a stub setting it `true` stands in
    # for "downloaded" here regardless of the underlying status string.
    context 'when the termination requested a data export that has been downloaded (delivered)' do
      let(:delivered_export_termination) { termination_data.merge('data_export_request_id' => 'export-2') }

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ delivered_export_termination ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_export_requests/export-2')
          .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-2', 'status' => 'completed', 'delivered_for_deletion' => true } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return('success' => true, 'data' => users_data)
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => delivered_export_termination)
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'proceeds with deleting account data as normal' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")

        job.execute
      end

      it 'completes the termination' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'completed')
          )
          .and_return('success' => true, 'data' => delivered_export_termination)

        job.execute
      end

      # IMP-0310a1351dab review round 2, item 2: only the termination's OWN
      # export may ever be exempted server-side — the worker must tell the
      # server which one that is.
      it "passes the termination's own data_export_request_id to the delete call" do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/data_export_requests", { own_export_request_id: 'export-2' })
          .and_return('success' => true, 'data' => { 'count' => 5, 'deferred' => 0 })

        job.execute
      end

      it 'records the real deleted count rather than an unconditional entry' do
        appended = []
        allow(api_client).to receive(:patch) do |_path, payload|
          appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
          { 'success' => true, 'data' => delivered_export_termination }
        end

        job.execute

        expect(appended).to include(hash_including(event: 'deleted_export_requests', count: 5))
      end

      # The archive is written to THIS host's tmp directory by
      # Compliance::DataExportJob and the server deletes only its own
      # filesystem, so the worker removes what the server reports it deleted.
      context 'when the server reports the archive paths of the export rows it deleted' do
        # A private, owner-only directory standing in for the worker's export
        # directory, so the trust check on it holds and no shared tmp is used.
        let(:export_root) { Dir.mktmpdir('powernode-exports').tap { |d| File.chmod(0o700, d) } }
        let(:archive_path) { File.join(export_root, "export_#{SecureRandom.hex(4)}.json") }

        before do
          allow(Compliance::DataExportJob).to receive(:export_dir).and_return(export_root)
          File.write(archive_path, '{}')
          allow(api_client).to receive(:delete)
            .with("/api/v1/internal/accounts/#{account_id}/data_export_requests", anything)
            .and_return('success' => true, 'data' => { 'count' => 1, 'deferred' => 0, 'file_paths' => [ archive_path ] })
        end

        after { FileUtils.rm_rf(export_root) }

        it 'removes the archive from the worker host' do
          job.execute

          expect(File.exist?(archive_path)).to be false
        end

        it 'does not fail the termination when the archive cannot be removed' do
          allow(File).to receive(:delete).and_raise(Errno::EACCES)
          expect(job).to receive(:log_warn).with(/left on the worker host \(failed\)/)
          expect(api_client).to receive(:patch)
            .with("/api/v1/internal/account_terminations/#{termination_id}", hash_including(status: 'completed'))
            .and_return('success' => true, 'data' => delivered_export_termination)

          expect { job.execute }.not_to raise_error

          expect(File.exist?(archive_path)).to be true
        end

        it 'never deletes a reported path outside the export directory' do
          outside = Tempfile.new('not-an-export')
          outside.close
          allow(api_client).to receive(:delete)
            .with("/api/v1/internal/accounts/#{account_id}/data_export_requests", anything)
            .and_return('success' => true, 'data' => { 'count' => 1, 'deferred' => 0, 'file_paths' => [ outside.path ] })
          expect(job).to receive(:log_warn).with(/left on the worker host \(outside_export_dir\)/)

          job.execute

          expect(File.exist?(outside.path)).to be true
        ensure
          outside&.unlink
        end

        it 'copes with a server that reports no file_paths at all (older build)' do
          allow(api_client).to receive(:delete)
            .with("/api/v1/internal/accounts/#{account_id}/data_export_requests", anything)
            .and_return('success' => true, 'data' => { 'count' => 1, 'deferred' => 0 })

          expect { job.execute }.not_to raise_error
        end
      end

      # A deferral reported back by the server at this point would be
      # unexpected (export_ready_for_deletion? already confirmed this export
      # is resolved before deletion ever starts) — but if it happens anyway,
      # it must be recorded honestly rather than silently ignored.
      it 'records a server-reported deferral rather than assuming success' do
        allow(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/data_export_requests", anything)
          .and_return('success' => true, 'data' => { 'count' => 0, 'deferred' => 1 })

        appended = []
        allow(api_client).to receive(:patch) do |_path, payload|
          appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
          { 'success' => true, 'data' => delivered_export_termination }
        end

        job.execute

        expect(appended).to include(hash_including(event: 'export_deletion_deferred'))
        expect(appended).not_to include(hash_including(event: 'deleted_export_requests'))
      end
    end

    # Operator ruling 2026-09-24: 'completed' alone is NOT delivered — the
    # user gets the full 7-day download window before its row (and the
    # account behind it) can be removed.
    context 'when the termination requested a data export that is completed but not yet downloaded (window still open)' do
      let(:undelivered_completed_termination) { termination_data.merge('data_export_request_id' => 'export-2a') }

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ undelivered_completed_termination ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_export_requests/export-2a')
          .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-2a', 'status' => 'completed', 'delivered_for_deletion' => false, 'created_at' => 30.minutes.ago.iso8601 } })
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => undelivered_completed_termination)
      end

      it 'defers deletion instead of removing an export the user has not yet retrieved' do
        expect(api_client).not_to receive(:delete)

        job.execute
      end

      it 'does not count as processed' do
        result = job.execute

        expect(result[:processed]).to eq(0)
      end

      it 'does not attempt to re-queue or retry a merely-undelivered (not failed) export' do
        expect(Compliance::DataExportJob).not_to receive(:perform_async)

        job.execute
      end

      # Review round 3, item 4: this is the ruling working exactly as
      # designed (the user gets the full 7-day window) — not something an
      # operator should ever be paged about, even after many sweeps' worth
      # of deferrals.
      context 'and it has already been deferred well past EXPORT_STALL_WARNING_DEFERRAL_COUNT times' do
        let(:long_waiting_termination) do
          deferral_entries = Array.new(10) { |i| { 'event' => 'export_pending_deferred', 'at' => (10 - i).days.ago.iso8601 } }
          undelivered_completed_termination.merge('termination_log' => [ seeded_reminder_entry ] + deferral_entries)
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ long_waiting_termination ])
        end

        it 'never writes export_stalled_warning for a benign, still-open download window' do
          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => long_waiting_termination }
          end

          job.execute

          expect(appended).not_to include(hash_including(event: 'export_stalled_warning'))
        end

        it 'does not log a stall warning message either' do
          expect(job).not_to receive(:log_warn).with(/deferred .* times without resolving/)

          job.execute
        end
      end
    end

    # Operator ruling 2026-09-24: a failed export is RESET and RE-QUEUED
    # (bounded), not treated as "nothing left to deliver" — replaces the
    # BLOCKER the review flagged (failed used to count as ready
    # unconditionally, deleting an export that had delivered nothing).
    context 'when the termination requested a data export that has failed' do
      context 'and it is below the retry limit' do
        let(:failed_export_termination) { termination_data.merge('data_export_request_id' => 'export-3') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ failed_export_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
            .and_return('success' => true, 'data' => [])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-3')
            .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-3', 'status' => 'failed', 'delivered_for_deletion' => false, 'metadata' => {} } })
          allow(api_client).to receive(:patch).and_return('success' => true, 'data' => failed_export_termination)
        end

        it 'does not proceed with deleting account data' do
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'resets the export via action_type: retry and re-queues Compliance::DataExportJob' do
          expect(api_client).to receive(:patch)
            .with('/api/v1/internal/data_export_requests/export-3', { action_type: 'retry' })
            .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-3', 'metadata' => { 'delivery_retry_count' => 1 } } })
          expect(Compliance::DataExportJob).to receive(:perform_async).with('export-3')

          job.execute
        end

        it 'does not count as processed (a retry is a deferral, not completed work)' do
          result = job.execute

          expect(result[:processed]).to eq(0)
        end
      end

      context 'and it has already failed EXPORT_DELIVERY_RETRY_LIMIT times' do
        let(:permanently_failed_termination) { termination_data.merge('data_export_request_id' => 'export-3b') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ permanently_failed_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
            .and_return('success' => true, 'data' => [])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-3b')
            .and_return(
              'success' => true,
              'data' => {
                'data_export_request' => {
                  'id' => 'export-3b', 'status' => 'failed', 'delivered_for_deletion' => false,
                  'metadata' => { 'delivery_retry_count' => Compliance::AccountTerminationJob::EXPORT_DELIVERY_RETRY_LIMIT }
                }
              }
            )
          allow(api_client).to receive(:patch).and_return('success' => true, 'data' => permanently_failed_termination)
          allow(api_client).to receive(:post).and_return('success' => true)
        end

        it 'does not retry again once the limit is reached' do
          expect(api_client).not_to receive(:patch)
            .with('/api/v1/internal/data_export_requests/export-3b', { action_type: 'retry' })
          expect(Compliance::DataExportJob).not_to receive(:perform_async)

          job.execute
        end

        it 'parks the termination with a once-only log entry' do
          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => permanently_failed_termination }
          end

          job.execute

          expect(appended).to include(hash_including(event: 'export_delivery_parked'))
        end

        it 'never deletes account data while the export remains undelivered' do
          expect(api_client).not_to receive(:delete)

          job.execute
        end

        it 'does not write a second export_delivery_parked entry once one already exists' do
          already_parked = permanently_failed_termination.merge(
            'termination_log' => permanently_failed_termination['termination_log'] + [
              { 'event' => 'export_delivery_parked', 'at' => 1.day.ago.iso8601 }
            ]
          )
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
            .and_return('success' => true, 'data' => [ already_parked ])

          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => already_parked }
          end

          job.execute

          expect(appended).not_to include(hash_including(event: 'export_delivery_parked'))
        end

        # Review round 4: this job used to ALSO POST an alert itself here
        # (removed — it was a no-op against notifications#send_notification,
        # which resolves recipients from `user_ids`, never present in this
        # job's account_id-only payload). The real alert
        # (SecurityAlertService, via the account_terminations PATCH this job
        # already makes above) is server-side now — see
        # Api::V1::Internal::AccountTerminationsController#update and its
        # own spec. This job has no seam left to assert on for the alert
        # itself; what it CAN assert is that it no longer makes the broken
        # call at all.
        it 'does not POST to the broken notifications#send_notification seam' do
          expect(api_client).not_to receive(:post)
            .with('/api/v1/internal/notifications/send', hash_including(type: 'export_delivery_parked'))

          job.execute
        end
      end
    end

    # IMP-0310a1351dab review round 2, item 3: 'expired' (the download window
    # has passed — given up) counts as resolved for deletion, the same as
    # 'completed'/'failed'.
    context 'when the termination requested a data export that has expired (download window passed)' do
      let(:expired_export_termination) { termination_data.merge('data_export_request_id' => 'export-5') }

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return('success' => true, 'data' => [ expired_export_termination ])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'processing' })
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_export_requests/export-5')
          .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-5', 'status' => 'expired', 'delivered_for_deletion' => true } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return('success' => true, 'data' => users_data)
        allow(api_client).to receive(:patch).and_return('success' => true, 'data' => expired_export_termination)
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'proceeds with deleting account data (an expired export has given up its delivery window)' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")

        job.execute
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

      # IMP-0310a1351dab: a RESUMED stranded row is the one case that needs
      # an explicit revert write when its export isn't ready — unlike a
      # fresh grace_period row (already re-selectable as-is by the normal
      # query), no query ever re-selects a 'processing' row except this
      # stranded-check path, so leaving it untouched would depend on that
      # same heuristic re-detecting it as stranded again next sweep instead
      # of being immediately re-checkable.
      context 'and it has been idle past the staleness threshold, with its own data export still undelivered' do
        let(:stranded_export_termination) do
          termination_data.merge(
            'status' => 'processing', 'processing_started_at' => 7.hours.ago.iso8601,
            'data_export_request_id' => 'export-4'
          )
        end

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/account_terminations', { status: 'processing' })
            .and_return('success' => true, 'data' => [ stranded_export_termination ])
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_export_requests/export-4')
            .and_return('success' => true, 'data' => { 'data_export_request' => { 'id' => 'export-4', 'status' => 'processing', 'delivered_for_deletion' => false } })
        end

        it 'reverts it back to grace_period rather than leaving it stranded in processing' do
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/account_terminations/#{termination_id}",
              hash_including(status: 'grace_period')
            )
            .and_return('success' => true, 'data' => stranded_export_termination)

          job.execute
        end

        it 'records the deferral in the termination log' do
          appended = []
          allow(api_client).to receive(:patch) do |_path, payload|
            appended.concat(Array(payload[:termination_log_append])) if payload.is_a?(Hash)
            { 'success' => true, 'data' => stranded_export_termination }
          end

          job.execute

          expect(appended).to include(hash_including(event: 'export_pending_deferred'))
        end

        it 'does not begin deleting any account data' do
          expect(api_client).not_to receive(:delete)

          job.execute
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
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/account_terminations/#{other_termination_id}")
            .and_return('success' => true, 'data' => { 'id' => other_termination_id })
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
