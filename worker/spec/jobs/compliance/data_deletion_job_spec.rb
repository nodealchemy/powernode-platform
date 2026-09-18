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
      'user_email' => 'user@example.com',
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
        # `consents` is the only DELETABLE_DATA_TYPES entry that actually
        # calls out via api_client.delete — profile/audit_logs/payments use
        # PATCH (anonymize-in-place), and activity/files/settings/
        # communications/analytics have no backing data model in core and are
        # skipped without any call at all (UNSUPPORTED_DATA_TYPES).
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

    # S-B (IMP-b33a3ecca331 third review): grace_period_ends_at can be missing
    # — this was ALWAYS true before the matching server-side fix
    # (DataDeletionRequestsController#approve_request never set it, S-B) and
    # remains a data-integrity possibility worth guarding even with that
    # fixed. Would redden on a revert to the bare `Time.zone.parse(nil)` this
    # used to be: that raises TypeError, which this example's `not_to raise`
    # expectation on `execute` would catch as a failure, and the 'approved' ->
    # 'failed' PATCH this asserts would never have happened (the old crash
    # path wrote 'failed' too, but via the OUTER rescue — after `raise e`
    # propagated the TypeError back out of `execute`, so `job.execute` itself
    # RAISED rather than returning cleanly; the whole point of S-B is that it
    # no longer does).
    context 'when grace_period_ends_at is missing' do
      let(:broken_request) { deletion_request_data.merge('grace_period_ends_at' => nil) }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(broken_request))
        allow(api_client).to receive(:patch).and_return(show_response(broken_request))
      end

      it 'terminates the request as failed instead of crashing on Time.zone.parse(nil)' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'failed', error_message: /grace_period_ends_at/)
          )
          .and_return(show_response(broken_request))

        expect { job.execute(deletion_request_id) }.not_to raise_error
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
      # 'consents' is the only DELETABLE_DATA_TYPES entry routed to an actual
      # DELETE call; 'activity' has no backing data model in core
      # (UNSUPPORTED_DATA_TYPES) — there never was a generic
      # `/api/v1/internal/data_deletion/:type` route for either (see
      # #delete_data_type's comment), so a partial request naming both
      # exercises the "one routed, one skipped" split this job actually makes.
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
                hash_including(data_type: 'activity', action: 'skipped', reason: 'no_backing_data_model')
              )
            )
          )
          .and_return(show_response(partial_request))

        job.execute(deletion_request_id)
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
    # anonymize_audit_logs is called unconditionally by process_full_deletion,
    # OUTSIDE delete_data_type's own internal per-type rescue, so an error
    # there reaches the outer rescue as a raw, non-PartialDeletionFailure
    # exception and DOES attempt this write. Would redden on a revert to a
    # bare (non-nested) `patch_deletion_request!` call in the outer rescue:
    # the write's own exception ("Failed to update data deletion request...")
    # would replace `e` on the implicit re-raise, so `job.execute` would
    # raise THAT message instead of the original domain failure.
    context 'when an unexpected error occurs mid-processing and the failed-status write also fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(show_response(deletion_request_data))
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 5 })
        # General patch stub FIRST (least specific — matches whatever none of
        # the narrower ones below claim, e.g. the 'profile' anonymize call
        # process_full_deletion also makes). instance_double is a verifying
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
