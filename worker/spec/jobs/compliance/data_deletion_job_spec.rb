# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::DataDeletionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:deletion_request_id) { 'del-req-123' }
  let(:user_id) { 'user-456' }
  let(:account_id) { 'account-789' }
  let(:job_args) { deletion_request_id }

  let(:deletion_request_data) do
    {
      'id' => deletion_request_id,
      'user_id' => user_id,
      'account_id' => account_id,
      'status' => 'approved',
      'deletion_type' => 'full',
      # The internal show carries the address snapshotted at request time
      # (IMP-b719328ddeb9); the user's own email is erased by this very job.
      'notification_email' => 'snapshot@example.com',
      'grace_period_ends_at' => 1.day.ago.iso8601,
      'data_types_to_retain' => []
    }
  end

  # Wraps a fixture the way Api::V1::Internal::DataDeletionRequestsController
  # #show actually responds: `render_success({ data_deletion_request: {...} })`
  # -> `{"success"=>true,"data"=>{"data_deletion_request"=>{...}}}` — ONE level
  # deeper than a flat `data: {...}`. String-keyed throughout (IMP-b33a3ecca331
  # third review, BLOCKER 1): BackendApiClient#handle_response returns the
  # Faraday-parsed JSON body VERBATIM on 2xx — string keys, never symbolized —
  # and raises ApiError on any non-2xx, never a symbol-keyed {success:, data:}
  # envelope. Every double in this file mirrors that exact shape.
  def show_response(request_hash)
    { 'success' => true, 'data' => { 'data_deletion_request' => request_hash } }
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

    context 'when deletion request is approved and grace period expired' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'fetches the deletion request from API' do
        # `.and_return` is load-bearing: a narrower `expect(...).with(...)` on
        # the SAME args as the `before` block's `allow` becomes the match
        # RSpec uses for calls with those args (most recently defined wins) —
        # with no return value it would answer `nil`, and `execute`'s
        # `response['success']` guard would raise NoMethodError on nil.
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      it 'updates status to processing' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'processing')
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      it 'deletes user data types' do
        # consents/settings/communications/files call out via
        # api_client.delete; profile/audit_logs/payments use PATCH
        # (anonymize-in-place). 'activity' and 'analytics' are withdrawn from
        # DELETABLE_DATA_TYPES entirely (IMP-bf52b4da135b) and are no longer
        # walked on a full deletion at all — UNSUPPORTED_DATA_TYPES now only
        # covers them arriving on a legacy row.
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")
          .and_return('success' => true, 'data' => { 'count' => 5 })

        job.execute(deletion_request_id)
      end

      it 'anonymizes audit logs' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})

        job.execute(deletion_request_id)
      end

      it 'marks request as completed' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'completed')
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      it 'sends completion notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'data_deletion_complete')
          )

        job.execute(deletion_request_id)
      end

      # IMP-b719328ddeb9: this used to read deletion_request['user_email'], a
      # key the server never serialized, so the notice went out with email: nil.
      it 'addresses the completion notification to the snapshotted address' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'data_deletion_complete', email: 'snapshot@example.com')
          )

        job.execute(deletion_request_id)
      end

      it 'never writes the snapshotted address to the log' do
        job.execute(deletion_request_id)

        %i[log_info log_error log_warn].each do |logger|
          expect(job).not_to have_received(logger).with(/snapshot@example\.com/)
        end
      end

      context 'when the request carries no snapshot (a legacy row)' do
        let(:deletion_request_data) { super().except('notification_email') }

        it 'sends nothing to a nil address, warns, and still completes the request' do
          expect(api_client).not_to receive(:post)
            .with('/api/v1/internal/notifications/send', anything)
          expect(api_client).to receive(:patch)
            .with(
              "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
              hash_including(status: 'completed')
            )
            .and_return(show_response(deletion_request_data))

          job.execute(deletion_request_id)

          expect(job).to have_received(:log_warn).with(/no notification address/i)
        end
      end

      context 'when the snapshot is blank' do
        let(:deletion_request_data) { super().merge('notification_email' => '') }

        it 'does not send to a blank address' do
          expect(api_client).not_to receive(:post)
            .with('/api/v1/internal/notifications/send', anything)

          job.execute(deletion_request_id)

          expect(job).to have_received(:log_warn).with(/no notification address/i)
        end
      end
    end

    context 'when deletion request is not approved' do
      let(:unapproved_request) { deletion_request_data.merge('status' => 'pending') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(unapproved_request))
      end

      it 'skips processing' do
        expect(api_client).not_to receive(:patch)
        expect(job).to receive(:log_info).with(/not approved/)

        job.execute(deletion_request_id)
      end
    end

    # (d) IMP-b33a3ecca331 third review, BLOCKER 1 new example: a 'processing'
    # request (one a prior Sidekiq attempt left mid-flight — see #execute's
    # comment on why 'processing' is accepted alongside 'approved') is
    # RESUMED, not skipped. Would redden on a revert to an 'approved'-only
    # guard (the state before this was first fixed): the job would then hit
    # the "not approved or processing, skipping" branch and return without
    # ever reaching the 'completed' write, silently abandoning a request that
    # already has real (possibly partial) deletion work in flight, with no
    # guard anywhere else that would ever pick it back up (nothing re-queues
    # a 'processing' request except this same job being retried).
    context 'when resuming a request a prior attempt left in processing' do
      let(:resuming_request) { deletion_request_data.merge('status' => 'processing') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(resuming_request))
        allow(api_client).to receive(:patch).and_return(show_response(resuming_request))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'does not take the skip branch the way a pending/rejected request would' do
        expect(job).not_to receive(:log_info).with(/not approved or processing/)

        job.execute(deletion_request_id)
      end

      it 'proceeds through to the completed write (idempotent re-run, not abandoned)' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'completed')
          )
          .and_return(show_response(resuming_request))

        job.execute(deletion_request_id)
      end
    end

    context 'when still in grace period' do
      let(:in_grace_request) { deletion_request_data.merge('grace_period_ends_at' => 1.day.from_now.iso8601) }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(in_grace_request))
      end

      it 'skips processing' do
        expect(api_client).not_to receive(:patch)
        expect(job).to receive(:log_info).with(/grace period/)

        job.execute(deletion_request_id)
      end
    end

    # IMP-26adf1c79c7a: the grace period is the data subject's cancellation
    # window, so a blank grace_period_ends_at fails CLOSED — the job neither
    # crashes on Time.zone.parse(nil) (S-B, IMP-b33a3ecca331) nor writes ANY
    # status. In particular never 'failed': the request was never processed,
    # and 'failed' would un-block the user's `.active` guard and be shown to
    # them as a failed erasure.
    context 'when grace_period_ends_at is missing' do
      let(:broken_request) { deletion_request_data.merge('grace_period_ends_at' => nil) }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(broken_request))
      end

      it 'exits without ANY status write (no failed, no processing) and does not raise' do
        expect(api_client).not_to receive(:patch)
        expect(api_client).not_to receive(:delete)
        expect(job).to receive(:log_error).with(/no grace_period_ends_at/)

        expect { job.execute(deletion_request_id) }.not_to raise_error
      end
    end

    # The worker's clock says the grace period ended, but the SERVER (the
    # authority) refuses the approved -> processing start. The job must exit
    # with no further write and no erasure call.
    context 'when the server refuses the approved -> processing start' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
      end

      def refusal(code)
        BackendApiClient::ApiError.new(
          'refused', 422, { 'success' => false, 'error' => 'refused', 'code' => code }
        )
      end

      %w[GRACE_PERIOD_NOT_ENDED INVALID_STATUS_TRANSITION].each do |code|
        it "exits after the single refused start and writes nothing else (#{code})" do
          expect(api_client).to receive(:patch).once
            .with(
              "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
              hash_including(status: 'processing')
            )
            .and_raise(refusal(code))
          expect(api_client).not_to receive(:delete)
          expect(api_client).not_to receive(:post)

          expect { job.execute(deletion_request_id) }.not_to raise_error
        end
      end

      it 'never writes failed for the refused request' do
        allow(api_client).to receive(:patch).and_raise(refusal('GRACE_PERIOD_NOT_ENDED'))
        expect(api_client).not_to receive(:patch).with(anything, hash_including(status: 'failed'))

        job.execute(deletion_request_id)
      end

      it 'still raises for a 422 that is not a start refusal' do
        allow(api_client).to receive(:patch)
          .and_raise(BackendApiClient::ApiError.new('invalid', 422, { 'code' => 'SOMETHING_ELSE' }))

        expect { job.execute(deletion_request_id) }.to raise_error(BackendApiClient::ApiError)
      end

      it 'still raises for a server error' do
        allow(api_client).to receive(:patch).and_raise(BackendApiClient::ApiError.new('boom', 500))

        expect { job.execute(deletion_request_id) }.to raise_error(BackendApiClient::ApiError)
      end
    end

    # A refusal only means "do not process" for a request that is STARTING.
    # A 'processing' request is a retry resuming: a refused
    # processing -> processing write is a real fault, not a clean exit.
    context 'when a resuming request gets a refused write' do
      let(:resuming_request) { deletion_request_data.merge('status' => 'processing') }

      it 'raises instead of silently exiting' do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(resuming_request))
        allow(api_client).to receive(:patch)
          .and_raise(BackendApiClient::ApiError.new('refused', 422, { 'code' => 'INVALID_STATUS_TRANSITION' }))

        expect { job.execute(deletion_request_id) }.to raise_error(BackendApiClient::ApiError)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return('success' => false, 'error' => 'Not found')
      end

      it 'raises an error' do
        expect { job.execute(deletion_request_id) }
          .to raise_error(/Failed to fetch deletion request/)
      end
    end

    context 'with partial deletion type' do
      # 'consents' is routed to a real DELETE call; 'activity' is a WITHDRAWN
      # type that only a legacy row can still carry (UNSUPPORTED_DATA_TYPES)
      # and has no category-level erasure path, so it is skipped without any
      # call. There never was a generic `/api/v1/internal/data_deletion/:type`
      # route for either (see #delete_data_type's comment), so a partial
      # request naming both exercises the "one routed, one skipped" split
      # this job actually makes.
      let(:partial_request) do
        deletion_request_data.merge(
          'deletion_type' => 'partial',
          'data_types_to_delete' => %w[consents activity]
        )
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(partial_request))
        allow(api_client).to receive(:patch).and_return(show_response(partial_request))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 3 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'deletes the routed type and records the unsupported type as skipped, not deleted' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")
          .and_return('success' => true, 'data' => { 'count' => 3 })

        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              deletion_log: array_including(
                hash_including(data_type: 'consents', action: 'deleted', records_affected: 3),
                hash_including(data_type: 'activity', action: 'skipped', reason: 'no_erasure_path')
              )
            )
          )
          .and_return(show_response(partial_request))

        job.execute(deletion_request_id)
      end
    end

    # IMP-bf52b4da135b — the two DELETABLE_DATA_TYPES entries that have a
    # per-user backing model AND a clean erasure path (the users preference
    # columns; Notification + EmailDelivery) now route to erasure endpoints
    # of their own instead of being lumped in with the types that have no
    # erasure path at all. Before this they were recorded as
    # `no_erasure_path` skips, which was accurate for 'activity' and
    # 'analytics' but wrong for these two: the data existed and survived.
    context 'with the newly-backed data types' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 4 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'erases the user\'s settings' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/settings")
          .and_return('success' => true, 'data' => { 'count' => 1 })

        job.execute(deletion_request_id)
      end

      it 'erases the user\'s communications' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/communications")
          .and_return('success' => true, 'data' => { 'count' => 4 })

        job.execute(deletion_request_id)
      end

      it 'records them as deleted with a real count, not as skipped' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              deletion_log: array_including(
                hash_including(data_type: 'settings', action: 'deleted', records_affected: 4),
                hash_including(data_type: 'communications', action: 'deleted', records_affected: 4)
              )
            )
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      it 'no longer walks the withdrawn types on a full deletion' do
        # 'activity' and 'analytics' are withdrawn from
        # DataManagement::DeletionRequest::DELETABLE_DATA_TYPES — a full
        # deletion must not manufacture log entries for categories the
        # platform no longer offers.
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              deletion_log: satisfy do |log|
                log.none? { |entry| %w[activity analytics].include?(entry[:data_type]) }
              end
            )
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end
    end

    # IMP-d97f6e3bbc2b — `files` is advertised again, backed by
    # FileManagement::Erasure behind DELETE /api/v1/internal/users/:id/files.
    # The server erases ONE bounded batch per request and returns a cursor;
    # this job walks it until nothing remains. A file the server could not
    # erase — held by a referent, or a blob the provider did not remove — is
    # a failed erasure of the category, never a completed one.
    describe "the 'files' data type" do
      let(:files_path) { "/api/v1/internal/users/#{user_id}/files" }
      # Real-shaped cursors: the server rejects anything but a UUID with 422.
      let(:cursor_1) { SecureRandom.uuid }
      let(:cursor_2) { SecureRandom.uuid }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 1 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      def files_batch(count:, remaining:, cursor:, failed: [], retained: 0)
        {
          'success' => true,
          'data' => {
            'count' => count, 'erased' => true, 'failed' => failed,
            'remaining' => remaining, 'cursor' => cursor, 'retained_platform_artifacts' => retained
          }
        }
      end

      it 'walks the server cursor until nothing remains and records the total and what was retained' do
        expect(api_client).to receive(:delete).with(files_path).ordered
          .and_return(files_batch(count: 2, remaining: 1, cursor: cursor_1))
        expect(api_client).to receive(:delete).with(files_path, { after_id: cursor_1 }).ordered
          .and_return(files_batch(count: 1, remaining: 0, cursor: cursor_2, retained: 2))
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              deletion_log: array_including(
                hash_including(data_type: 'files', action: 'deleted', records_affected: 3,
                               retained_platform_artifacts: 2)
              )
            )
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      # Critic B, M2: a blob the provider could not remove is OPERATIONAL (the
      # store is down, unmounted, misconfigured) — a retry may clear it, and
      # the subject, anonymized by now, cannot re-file. So it must not end
      # the request `failed` (terminal, no re-arm). The request stays
      # `processing` with the error on record and the raise hands it to
      # Sidekiq's retry, which resumes a `processing` row.
      it 'leaves the request retryable, not failed, when the server reports a blob it could not remove' do
        allow(api_client).to receive(:delete).with(files_path).and_return(
          files_batch(count: 0, remaining: 0, cursor: cursor_1,
                      failed: [ { 'id' => 'file-1', 'kind' => 'error', 'reason' => 'storage_removal_failed' } ])
        )
        writes = []
        allow(api_client).to receive(:patch) do |path, payload|
          writes << payload if path.end_with?(deletion_request_id)
          show_response(deletion_request_data)
        end

        expect { job.execute(deletion_request_id) }
          .to raise_error(Compliance::DataDeletionJob::RetryableErasureFailure, /storage_removal_failed/)

        expect(writes.map { |w| w[:status] }.compact).to eq(%w[processing])
        expect(writes).to include(hash_including(error_message: /files.*storage_removal_failed/))
        expect(writes).not_to include(hash_including(status: 'failed'))
        expect(writes).not_to include(hash_including(status: 'completed'))
      end

      it 'caps the failure text to a bounded sample rather than naming every file' do
        failed = Array.new(40) { |i| { 'id' => "file-#{i}", 'kind' => 'error', 'reason' => 'storage_removal_failed' } }
        allow(api_client).to receive(:delete).with(files_path).and_return(
          files_batch(count: 0, remaining: 0, cursor: cursor_1, failed: failed)
        )
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))

        expect { job.execute(deletion_request_id) }.to raise_error(
          Compliance::DataDeletionJob::RetryableErasureFailure,
          /40 file\(s\) not erased.*and 30 more/
        )
      end

      it 'fails the request for a held file too — the subject\'s file was not erased' do
        allow(api_client).to receive(:delete).with(files_path).and_return(
          files_batch(count: 3, remaining: 0, cursor: cursor_1,
                      failed: [ { 'id' => 'file-9', 'kind' => 'held', 'reason' => 'held_by_boot_image' } ])
        )
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'failed',
              deletion_log: array_including(
                hash_including(data_type: 'files', action: 'failed', error: /held_by_boot_image/)
              )
            )
          )
          .and_return(show_response(deletion_request_data))

        expect { job.execute(deletion_request_id) }
          .to raise_error(Compliance::DataDeletionJob::PartialDeletionFailure)
      end

      # Critic B, H2: an OLDER server has no users/:id/files route at all, so
      # what a new worker actually gets is a 404 — not an `erased: false`
      # body (that shape only ever existed on the accounts route). Treated
      # as the skip it is; the alternative was a terminal `failed` on every
      # full deletion after `profile` had already been anonymized.
      it 'records a skip with reason no_erasure_path when an older server answers 404' do
        allow(api_client).to receive(:delete).with(files_path).and_raise(
          BackendApiClient::ApiError.new('Resource not found', 404, { 'success' => false, 'error' => 'Not found' })
        )
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              deletion_log: array_including(
                hash_including(data_type: 'files', action: 'skipped', reason: 'no_erasure_path')
              )
            )
          )
          .and_return(show_response(deletion_request_data))

        job.execute(deletion_request_id)
      end

      it 'does not call the files endpoint when the request retains files' do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data.merge('data_types_to_retain' => %w[files])))

        job.execute(deletion_request_id)

        expect(api_client).not_to have_received(:delete).with(files_path)
        expect(api_client).not_to have_received(:delete).with(files_path, anything)
      end
    end

    # IMP-bf52b4da135b — `data_types_to_retain` naming 'profile' was honoured
    # by the per-type loop (which logged it as retained) and then immediately
    # contradicted by an UNCONDITIONAL `anonymize_user(user_id)` call after
    # the loop. The data subject was told their profile was retained while
    # the user row was anonymized in place anyway.
    context 'when the request retains the profile' do
      let(:retain_profile_request) do
        deletion_request_data.merge('data_types_to_retain' => %w[profile])
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(retain_profile_request))
        allow(api_client).to receive(:patch).and_return(show_response(retain_profile_request))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 2 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'does not anonymize the user record' do
        job.execute(deletion_request_id)

        expect(api_client).not_to have_received(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize", anything)
      end

      it 'records the profile as retained rather than deleted' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              retention_log: array_including(hash_including(data_type: 'profile'))
            )
          )
          .and_return(show_response(retain_profile_request))

        job.execute(deletion_request_id)
      end

      it 'still erases the data types that were not retained' do
        # The retention must be scoped to 'profile' alone — it must not become
        # an excuse to skip the rest of the erasure.
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")
          .and_return('success' => true, 'data' => { 'count' => 2 })

        job.execute(deletion_request_id)
      end
    end

    context 'when the request does not retain the profile' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 2 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'anonymizes the user record exactly once' do
        # Control for the retention example above: making the call conditional
        # must not remove it from the default path. `exactly(1)` also pins the
        # removal of the redundant second call — the per-type loop's 'profile'
        # branch and the unconditional post-loop call used to both fire.
        job.execute(deletion_request_id)

        expect(api_client).to have_received(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize", anything)
          .exactly(1).time
      end
    end

    # IMP-ca3551dd27be — `data_types_to_retain` was binding for profile,
    # settings, consents and communications (the per-type loop) but IGNORED
    # for the other two DELETABLE_DATA_TYPES members: process_full_deletion
    # called anonymize_audit_logs / anonymize_payments UNCONDITIONALLY after
    # the loop, so a request that retained either still had it anonymized,
    # and the retention_log never mentioned it. These examples assert the
    # data SURVIVES (its endpoint is never called) when the type is retained.
    {
      'audit_logs' => [ 'Required for security and compliance auditing', ->(u, _a) { "/api/v1/internal/users/#{u}/anonymize_audit_logs" } ],
      'payments' => [ 'Required for tax and accounting purposes', ->(_u, a) { "/api/v1/internal/accounts/#{a}/anonymize_payments" } ]
    }.each do |retained_type, (expected_reason, endpoint_for)|
      context "when the request retains #{retained_type}" do
        let(:retaining_request) do
          deletion_request_data.merge('data_types_to_retain' => [ retained_type ])
        end

        before do
          allow(api_client).to receive(:get)
            .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
            .and_return(show_response(retaining_request))
          allow(api_client).to receive(:patch).and_return(show_response(retaining_request))
          allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 2 })
          allow(api_client).to receive(:post).and_return('success' => true)
        end

        it "never calls the #{retained_type} anonymize endpoint" do
          job.execute(deletion_request_id)

          expect(api_client).not_to have_received(:patch).with(endpoint_for.call(user_id, account_id), anything)
        end

        it "records #{retained_type} as retained with its reason, and not in the deletion_log" do
          job.execute(deletion_request_id)

          expect(api_client).to have_received(:patch).with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(
              status: 'completed',
              retention_log: array_including(hash_including(data_type: retained_type, reason: expected_reason)),
              deletion_log: satisfy { |log| log.none? { |entry| entry[:data_type] == retained_type } }
            )
          )
        end
      end
    end

    # Inverse oracle for the retention examples above: a fix that simply
    # stopped anonymizing audit logs and payments would pass every "survives"
    # assertion. Un-retained, each must still be anonymized — exactly once,
    # and RECORDED (the old unconditional calls ran but logged nothing).
    context 'when the request retains neither audit_logs nor payments' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 2 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'anonymizes audit logs and payments exactly once each' do
        job.execute(deletion_request_id)

        expect(api_client).to have_received(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", anything).exactly(1).time
        expect(api_client).to have_received(:patch)
          .with("/api/v1/internal/accounts/#{account_id}/anonymize_payments", anything).exactly(1).time
      end

      it 'records both as anonymized in the deletion_log' do
        job.execute(deletion_request_id)

        expect(api_client).to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(
            status: 'completed',
            deletion_log: array_including(
              hash_including(data_type: 'audit_logs', action: 'anonymized'),
              hash_including(data_type: 'payments', action: 'anonymized')
            )
          )
        )
      end
    end

    # The retain list every data-subject request actually carries:
    # DataManagement::DeletionRequest#set_defaults fills it with
    # LEGALLY_RETAINED_DATA_TYPES, and Api::V1::PrivacyController
    # #request_deletion never overrides it. None of the three names a
    # DELETABLE_DATA_TYPES member, so today it retains NOTHING: every category
    # is erased or anonymized and the retention_log stays empty. Pinned so
    # that mapping one of them onto a category (e.g. financial_records ->
    # payments) is a visible, deliberate change rather than a silent one.
    context 'with the production default retain list' do
      let(:default_retain_request) do
        deletion_request_data.merge('data_types_to_retain' => %w[financial_records tax_documents legal_agreements])
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(default_retain_request))
        allow(api_client).to receive(:patch).and_return(show_response(default_retain_request))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 1 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'erases or anonymizes every deletable type once and retains nothing' do
        job.execute(deletion_request_id)

        %w[anonymize anonymize_audit_logs].each do |action|
          expect(api_client).to have_received(:patch)
            .with("/api/v1/internal/users/#{user_id}/#{action}", anything).exactly(1).time
        end
        expect(api_client).to have_received(:patch)
          .with("/api/v1/internal/accounts/#{account_id}/anonymize_payments", anything).exactly(1).time
        %w[settings consents communications].each do |data_type|
          expect(api_client).to have_received(:delete)
            .with("/api/v1/internal/users/#{user_id}/#{data_type}").exactly(1).time
        end
        expect(api_client).to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(
            status: 'completed',
            retention_log: [],
            deletion_log: satisfy do |log|
              log.map { |entry| entry[:data_type] }.sort == described_class::DELETABLE_DATA_TYPES.sort
            end
          )
        )
      end
    end

    # Moving audit_logs/payments into the per-type loop also moves their
    # failures there: an audit-log anonymize that raises on a 'full' request
    # is now a recorded per-type failure (PartialDeletionFailure with the
    # full deletion_log), exactly like a failed consents delete — not a raw
    # error that reached the outer rescue with no per-type detail.
    context 'when the audit-log anonymize fails on a full deletion' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})
          .and_raise(BackendApiClient::ApiError.new('audit log service unavailable'))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 1 })
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'records audit_logs as a failed type and fails the request once with the per-type log' do
        expect { job.execute(deletion_request_id) }
          .to raise_error(described_class::PartialDeletionFailure, /audit_logs/)

        expect(api_client).to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(
            status: 'failed',
            deletion_log: array_including(hash_including(data_type: 'audit_logs', action: 'failed'))
          )
        ).once
      end
    end

    # Uniformity across EVERY DELETABLE_DATA_TYPES member (IMP-ca3551dd27be):
    # retained -> its endpoint is never called and it is in retention_log;
    # not retained -> its endpoint is called once and it is in deletion_log.
    # No member may be special-cased beside the loop.
    describe 'data_types_to_retain is binding for every deletable type' do
      endpoints = {
        'profile' => [ :patch, ->(u, _a) { "/api/v1/internal/users/#{u}/anonymize" } ],
        'audit_logs' => [ :patch, ->(u, _a) { "/api/v1/internal/users/#{u}/anonymize_audit_logs" } ],
        'payments' => [ :patch, ->(_u, a) { "/api/v1/internal/accounts/#{a}/anonymize_payments" } ],
        'settings' => [ :delete, ->(u, _a) { "/api/v1/internal/users/#{u}/settings" } ],
        'consents' => [ :delete, ->(u, _a) { "/api/v1/internal/users/#{u}/consents" } ],
        'communications' => [ :delete, ->(u, _a) { "/api/v1/internal/users/#{u}/communications" } ],
        # One batch per call; the stub's `count: 1` with no `remaining` is a
        # single batch, so "exactly once" holds for files too.
        'files' => [ :delete, ->(u, _a) { "/api/v1/internal/users/#{u}/files" } ]
      }

      it 'covers exactly the job\'s DELETABLE_DATA_TYPES' do
        expect(endpoints.keys).to match_array(described_class::DELETABLE_DATA_TYPES)
      end

      endpoints.each do |data_type, (verb, path_for)|
        context "for #{data_type}" do
          def stub_with(request)
            allow(api_client).to receive(:get)
              .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
              .and_return(show_response(request))
            allow(api_client).to receive(:patch).and_return(show_response(request))
            allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 1 })
            allow(api_client).to receive(:post).and_return('success' => true)
          end

          it 'is left untouched and logged as retained when retained' do
            stub_with(deletion_request_data.merge('data_types_to_retain' => [ data_type ]))

            job.execute(deletion_request_id)

            expect(api_client).not_to have_received(verb).with(path_for.call(user_id, account_id), any_args)
            expect(api_client).to have_received(:patch).with(
              "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
              hash_including(
                status: 'completed',
                retention_log: [ hash_including(data_type: data_type) ],
                deletion_log: satisfy { |log| log.none? { |entry| entry[:data_type] == data_type } }
              )
            )
          end

          it 'is erased exactly once and logged when not retained' do
            stub_with(deletion_request_data)

            job.execute(deletion_request_id)

            expect(api_client).to have_received(verb).with(path_for.call(user_id, account_id), any_args).exactly(1).time
            expect(api_client).to have_received(:patch).with(
              "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
              hash_including(
                status: 'completed',
                retention_log: [],
                deletion_log: array_including(hash_including(data_type: data_type))
              )
            )
          end
        end
      end
    end

    context 'with anonymization type' do
      let(:anonymize_request) { deletion_request_data.merge('deletion_type' => 'anonymize') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(anonymize_request))
        allow(api_client).to receive(:patch).and_return(show_response(anonymize_request))
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'anonymizes user instead of deleting' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize", anything)

        job.execute(deletion_request_id)
      end
    end

    context 'when a per-data-type deletion fails (partial GDPR erasure)' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:post).and_return('success' => true)
        # Most data types delete cleanly...
        allow(api_client).to receive(:delete)
          .and_return('success' => true, 'data' => { 'count' => 5 })
        # ...but 'consents' (the one DELETABLE_DATA_TYPES entry actually
        # routed to a DELETE call) raises (e.g. storage backend down).
        allow(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")
          .and_raise(BackendApiClient::ApiError.new('storage backend unavailable'))
      end

      it 'does not mark the request completed and re-raises so the failure is surfaced' do
        expect { job.execute(deletion_request_id) }.to raise_error(/consents/)

        expect(api_client).not_to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(status: 'completed')
        )
      end

      it 'marks the request failed and records the per-type error (not a phantom delete)' do
        expect { job.execute(deletion_request_id) }.to raise_error(StandardError)

        # The failed type is surfaced with its error, NOT recorded as a
        # successful zero-record deletion (which would be indistinguishable
        # from "nothing to delete").
        expect(api_client).to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(
            status: 'failed',
            deletion_log: array_including(
              hash_including(data_type: 'consents', action: 'failed')
            )
          )
        )

        expect(api_client).not_to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(
            deletion_log: array_including(
              hash_including(data_type: 'consents', action: 'deleted', records_affected: 0)
            )
          )
        )
      end

      it 'does not send the completion notification for a failed erasure' do
        expect { job.execute(deletion_request_id) }.to raise_error(StandardError)

        expect(api_client).not_to have_received(:post).with(
          '/api/v1/internal/notifications/send',
          hash_including(type: 'data_deletion_complete')
        )
      end

      # (5) IMP-b33a3ecca331 fourth review, new example: exactly ONE `failed`
      # PATCH, not two. PartialDeletionFailure (S-C) already wrote 'failed'
      # (with the full deletion_log/retention_log detail) before raising —
      # the outer rescue recognizes it and skips its own redundant write.
      # Would redden on a revert of that skip: the outer rescue's generic
      # `patch_deletion_request!(..., status: 'failed', error_message: ...)`
      # would fire a SECOND time, and the second write would now also 422
      # under the transition guard (failed -> failed isn't allowed) — but
      # `patch` is mocked here, so the count itself is what catches the
      # regression, not the 422.
      it 'PATCHes failed exactly once (the outer rescue skips its own redundant write)' do
        expect { job.execute(deletion_request_id) }.to raise_error(StandardError)

        expect(api_client).to have_received(:patch).with(
          "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
          hash_including(status: 'failed')
        ).once
      end
    end

    # (c) IMP-b33a3ecca331 third review, BLOCKER 1 new example: the ORIGINAL
    # error is re-raised even when the rescue's own 'failed'-status write also
    # fails. Deliberately NOT a PartialDeletionFailure (that path already
    # wrote 'failed' before raising and SKIPS this write entirely, per S-C) —
    # process_anonymization calls anonymize_audit_logs OUTSIDE
    # delete_data_type's own internal per-type rescue, so an error there
    # reaches the outer rescue as a raw, non-PartialDeletionFailure exception
    # and DOES attempt this write. (IMP-ca3551dd27be: this context used to
    # ride on a 'full' request, whose audit-log anonymize was ALSO an
    # unconditional out-of-loop call. That call now goes through the per-type
    # loop like every other DELETABLE_DATA_TYPES member, so a failure there is
    # a PartialDeletionFailure — the 'anonymize' request is the raw raise site
    # that remains.) Would redden on a revert to a
    # bare (non-nested) `patch_deletion_request!` call in the outer rescue:
    # the write's own exception ("Failed to update data deletion request...")
    # would replace `e` on the implicit re-raise, so `job.execute` would
    # raise THAT message instead of the original domain failure.
    context 'when an unexpected error occurs mid-processing and the failed-status write also fails' do
      let(:anonymize_request) { deletion_request_data.merge('deletion_type' => 'anonymize') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(anonymize_request))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        # General patch stub FIRST (least specific — matches whatever none of
        # the narrower ones below claim, e.g. the user anonymize call
        # process_anonymization makes first). instance_double is a verifying
        # double: any patch call matching NEITHER this NOR a narrower `.with`
        # below would raise a mock-framework error, not a StandardError the
        # job's own rescues would catch — so every real call site this run
        # makes needs a matching stub.
        allow(api_client).to receive(:patch).and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}", hash_including(status: 'processing'))
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})
          .and_raise(BackendApiClient::ApiError.new('audit log service unavailable'))
        allow(api_client).to receive(:patch)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}", hash_including(status: 'failed'))
          .and_return('success' => false, 'error' => 'write conflict')
      end

      it 're-raises the original processing error, not the status-write failure' do
        expect { job.execute(deletion_request_id) }.to raise_error(/audit log service unavailable/)
      end

      it 'logs the status-write failure without swallowing it silently' do
        expect(job).to receive(:log_error).with(/Failed to persist 'failed' status/)

        expect { job.execute(deletion_request_id) }.to raise_error(StandardError)
      end
    end
  end
end
