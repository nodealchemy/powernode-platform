# frozen_string_literal: true

module Api
  module V1
    module Internal
      class DataDeletionRequestsController < InternalBaseController
        before_action :set_deletion_request, only: [ :show, :update ]

        # GET /api/v1/internal/data_deletion_requests/:id
        def show
          render_success({ data_deletion_request: serialize_request(@deletion_request, include_details: true) })
        end

        # POST /api/v1/internal/data_deletion_requests
        def create
          @deletion_request = DataManagement::DeletionRequest.new(deletion_request_params)
          @deletion_request.status = "pending"

          if @deletion_request.save
            # Queue processing through the worker HTTP API seam
            queue_worker_deletion_job(@deletion_request.id)

            render_success({ data_deletion_request: serialize_request(@deletion_request) }, status: :created)
          else
            render_error(@deletion_request.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/internal/data_deletion_requests/:id
        def update
          case params[:action_type]
          when "approve"
            approve_request
          when "reject"
            reject_request
          when "execute"
            execute_request
          when "complete"
            complete_request
          else
            worker_status_update
          end
        end

        private

        # The action_type dispatch above guards each admin-facing transition
        # individually (approve_request requires pending?, execute_request
        # requires approved?, complete_request requires processing?). This
        # branch is the OTHER caller — Compliance::DataDeletionJob's raw,
        # no-action_type status-progress PATCHes — and until this fix it had
        # NO transition guard at all: any mTLS-enrolled worker principal could
        # set ANY valid model status (e.g. `completed` on a request that was
        # never approved), bypassing complete_request's own guard, its audit
        # row, and its user notification — effectively forging a GDPR
        # completion record (security-relevant, IMP-b33a3ecca331 review, S3).
        #
        # Mirrors the exact transitions Compliance::DataDeletionJob actually
        # makes (see the job's patch_deletion_request! call sites):
        # processing -> processing (a Sidekiq retry RESUMING a request left
        # mid-flight — see the job's 'processing' guard), processing ->
        # completed, processing -> failed.
        # approved -> processing is deliberately NOT in this static map: it is
        # the grace-period-protected start, and only
        # #start_processing_for_worker (DeletionRequest#start_processing!, the
        # single owner of that rule) may perform it. There is no approved ->
        # failed either: a request that was never processed is not 'failed'
        # (that would drop it out of PrivacyController's `.active` guard and
        # be shown to the data subject as a failed erasure).
        # A status-less PATCH (no `status` key at all) is not itself a
        # transition, but (nit, second review; extended fourth review, nit 3)
        # one carrying progress fields (completed_at/deletion_log/
        # retention_log/error_message/metadata/processing_started_at) IS a
        # status-adjacent write and is only meaningful while the request is
        # actively `processing` — a request that is `pending`/`approved` has
        # no processing run in flight to report progress for, and one that's
        # already terminal (completed/failed/rejected) has nothing left to
        # report. No real caller (job or admin action) sends any of these
        # status-less while NOT processing — `metadata`/`processing_started_at`
        # were the two remaining permitted fields NOT already covered; a
        # genuinely bare write carrying NONE of these keys (nothing left to
        # gate) is still always allowed.
        ALLOWED_WORKER_STATUS_TRANSITIONS = {
          "processing" => %w[processing completed failed]
        }.freeze

        STATUS_ADJACENT_KEYS = %i[
          completed_at deletion_log retention_log error_message metadata processing_started_at
        ].freeze

        # `with_lock` (second review, atomicity nit): the guard is now
        # re-checked INSIDE the lock against a freshly-reloaded row, so a
        # concurrent writer that changed this request's status between the
        # first (fail-fast) check and lock acquisition can't slip a write
        # through on stale assumptions. `transitioned` records whether the
        # write actually ran — not a status comparison — so a race landing on
        # some third status is still caught (mirrors AccountTerminationsController#update).
        #
        # `previous_status` (fourth review, nit 2) is captured INSIDE the
        # lock, off the freshly-reloaded record — capturing it before
        # `with_lock` would name whatever status this controller read BEFORE
        # the lock, which a concurrent writer could have already moved past;
        # the audit row must name the status this write actually transitioned
        # FROM, not a stale one.
        def worker_status_update
          requested_status = params[:status]

          if requested_status == "processing" && @deletion_request.approved?
            return start_processing_for_worker
          end

          unless worker_write_guard_passes?(requested_status, @deletion_request.status)
            return render_error(
              "Invalid status transition from '#{@deletion_request.status}' to '#{requested_status}'",
              status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
            )
          end

          transitioned = false
          previous_status = nil

          @deletion_request.with_lock do
            previous_status = @deletion_request.status

            unless worker_write_guard_passes?(requested_status, @deletion_request.status)
              raise ActiveRecord::Rollback
            end

            @deletion_request.update!(deletion_request_update_params)
            transitioned = true
          end

          unless transitioned
            return render_error(
              "Invalid status transition from '#{@deletion_request.status}' to '#{requested_status}' " \
              "(lost a concurrent update race)",
              status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
            )
          end

          if requested_status.present?
            log_internal_audit("data_deletion.status_transition", "DeletionRequest", @deletion_request.id,
                               account_id: @deletion_request.account_id,
                               from_status: previous_status, to_status: requested_status)
          end

          render_success({ data_deletion_request: serialize_request(@deletion_request) })
        rescue ActiveRecord::RecordInvalid
          render_error(@deletion_request.errors.full_messages.join(", "), status: :unprocessable_content)
        end

        def worker_write_guard_passes?(requested_status, current_status)
          if requested_status.present?
            (ALLOWED_WORKER_STATUS_TRANSITIONS[current_status] || []).include?(requested_status)
          elsif status_adjacent_write?
            current_status == "processing"
          else
            true
          end
        end

        # The worker's request for approved -> processing. The SERVER is the
        # authority on the grace period (the data subject's cancellation
        # window): the worker may pre-check, but a worker — or anything
        # holding a worker token — that skips its own check is still refused
        # here. #start_processing! re-checks under the row lock, so this is
        # also the at-most-once gate against a concurrent run-now or a second
        # worker. A refusal writes NOTHING to the row.
        def start_processing_for_worker
          started = @deletion_request.start_processing! do
            log_internal_audit("data_deletion.status_transition", "DeletionRequest", @deletion_request.id,
                               account_id: @deletion_request.account_id,
                               from_status: "approved", to_status: "processing")
          end

          if started
            render_success({ data_deletion_request: serialize_request(@deletion_request) })
          else
            render_start_refused
          end
        end

        # Why #start_processing! returned false, read off the CURRENT row: still
        # 'approved' means the grace period has not ended (or its end is
        # unset); anything else means another starter won the race.
        def render_start_refused
          @deletion_request.reload

          if @deletion_request.approved?
            render_error(grace_refusal_message, status: :unprocessable_content, code: "GRACE_PERIOD_NOT_ENDED")
          else
            render_error(
              "Invalid status transition from '#{@deletion_request.status}' to 'processing' " \
              "(lost a concurrent update race)",
              status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
            )
          end
        end

        def grace_refusal_message
          ends_at = @deletion_request.grace_period_ends_at
          return "Deletion request has no grace_period_ends_at; refusing to start processing" if ends_at.blank?

          "Grace period has not ended (ends at #{ends_at.iso8601}); refusing to start processing"
        end

        def status_adjacent_write?
          STATUS_ADJACENT_KEYS.any? { |key| params.key?(key) }
        end

        # Dispatch deletion processing through the worker HTTP API seam. The old
        # DataManagement::Deletion{Processing,Execution}Job classes never existed
        # (server or worker) and the server runs no Sidekiq/ActiveJob backend,
        # so enqueuing them raised NameError (500). Compliance::DataDeletionJob
        # is the worker job that processes DataManagement::DeletionRequest records.
        def queue_worker_deletion_job(deletion_request_id)
          WorkerApiClient.new.queue_job("Compliance::DataDeletionJob", [ deletion_request_id ], queue: "compliance")
          true
        rescue WorkerApiClient::ApiError => e
          Rails.logger.error "[DataDeletionRequests] Failed to queue Compliance::DataDeletionJob " \
                             "for #{deletion_request_id}: #{e.message}"
          false
        end

        def set_deletion_request
          @deletion_request = DataManagement::DeletionRequest.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data deletion request not found", status: :not_found)
        end

        def deletion_request_params
          params.require(:data_deletion_request).permit(
            :account_id, :user_id, :deletion_type, :reason,
            data_types_to_delete: [], data_types_to_retain: [], metadata: {}
          )
        end

        # The worker (Compliance::DataDeletionJob) is this branch's ONLY caller,
        # and it PATCHes a raw top-level JSON body — no `data_deletion_request:`
        # wrapper (this app is ActionController::API; there is no ParamsWrapper
        # to add one). `params.require(:data_deletion_request)` therefore raised
        # ActionController::ParameterMissing on every status-transition write the
        # job makes (processing/completed/failed/error_message-only), rescued by
        # ApiResponse into a 400 the job never checked — so none of those writes
        # ever actually persisted (IMP-b33a3ecca331). Read these fields at the
        # top level instead, mirroring the sibling AccountTerminationsController
        # #update, which already does. `status` stays guarded by the model's own
        # inclusion validation (DataManagement::DeletionRequest), not re-checked
        # here.
        def deletion_request_update_params
          params.permit(
            :status, :processing_started_at, :completed_at, :error_message,
            deletion_log: [ :data_type, :action, :error, :records_affected, :processed_at, :reason,
                            :retained_platform_artifacts ],
            retention_log: [ :data_type, :reason, :processed_at ],
            metadata: {}
          )
        end

        def approve_request
          unless @deletion_request.pending?
            return render_error("Request is not pending", status: :unprocessable_content)
          end

          # Validate processed_by_id if provided
          processed_by = nil
          if params[:processed_by_id].present?
            processed_by = User.find_by(id: params[:processed_by_id])
            unless processed_by
              return render_error("Invalid processed_by_id", status: :unprocessable_content)
            end
          end

          # grace_period_ends_at (IMP-b33a3ecca331 third review, S-B): this
          # write used to omit it entirely, while DataManagement::
          # DeletionRequest#approve! (the model's own approval path, unused
          # by this controller) sets it. Compliance::DataDeletionJob reads
          # this field unconditionally once a request is approved/processing
          # and previously crashed on `Time.zone.parse(nil)` for every
          # request approved through this endpoint — the ONLY approval path
          # that exists (nothing here calls the model method) — turning
          # every approval into a crash-loop rather than a grace period.
          @deletion_request.update!(
            status: "approved",
            approved_at: Time.current,
            grace_period_ends_at: DataManagement::DeletionRequest::GRACE_PERIOD_DAYS.days.from_now,
            processed_by_id: processed_by&.id
          )
          log_internal_audit("data_deletion.approve", "DeletionRequest", @deletion_request.id,
                             account_id: @deletion_request.account_id, user_id: @deletion_request.user_id)

          # Send approval notification
          NotificationService.send_email(
            template: "data_deletion_approved",
            user_id: @deletion_request.user_id,
            data: {
              request_id: @deletion_request.id
            }
          )

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion request approved"
          )
        end

        # DeletionRequest#reject! owns the transition: it re-checks the status
        # under the row lock, so a request whose erasure started after this
        # controller loaded it is refused with nothing written. The audit row
        # is written inside that locked transaction; the rejection notice is
        # sent by reject! only once the transition has committed
        # (IMP-01dc7cf9d2ef).
        def reject_request
          unless @deletion_request.can_be_cancelled?
            return render_error("Request cannot be rejected", status: :unprocessable_content)
          end

          if params[:reason].blank?
            return render_error("Rejection reason is required", status: :unprocessable_content)
          end

          rejected_by = User.find_by(id: params[:rejected_by_id]) if params[:rejected_by_id].present?
          if params[:rejected_by_id].present? && rejected_by.nil?
            return render_error("Invalid rejected_by_id", status: :unprocessable_content)
          end

          rejected = @deletion_request.reject!(rejected_by, params[:reason]) do
            log_internal_audit("data_deletion.reject", "DeletionRequest", @deletion_request.id,
                               account_id: @deletion_request.account_id, reason: params[:reason])
          end
          unless rejected
            return render_error("Request cannot be rejected (status is now '#{@deletion_request.status}')",
                                status: :unprocessable_content)
          end

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion request rejected"
          )
        end

        def execute_request
          unless @deletion_request.approved?
            return render_error("Request must be approved before execution", status: :unprocessable_content)
          end

          # Run-now is REFUSED inside the grace period, never bypassed
          # (IMP-26adf1c79c7a); nothing is enqueued and the row stays approved.
          # The audit row is written inside the start's locked transaction, so
          # a failed audit rolls the start back; the enqueue stays AFTER the
          # commit.
          started = @deletion_request.start_processing! do
            log_internal_audit("data_deletion.execute", "DeletionRequest", @deletion_request.id,
                               account_id: @deletion_request.account_id)
          end
          return render_start_refused unless started

          # Execute deletion in background through the worker HTTP API seam.
          # The row is already 'processing' (committed), so a failed enqueue
          # is reported to the caller as an error, never a success envelope —
          # there is deliberately no recovery state here.
          unless queue_worker_deletion_job(@deletion_request.id)
            Rails.logger.error "[DataDeletionRequests] Deletion request #{@deletion_request.id} is " \
                               "'processing' but its worker job could NOT be queued; it will not run until re-enqueued"
            return render_error(
              "Deletion started but the worker job could not be queued",
              status: :bad_gateway, code: "WORKER_ENQUEUE_FAILED"
            )
          end

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion execution started"
          )
        end

        def complete_request
          unless @deletion_request.processing?
            return render_error("Request is not processing", status: :unprocessable_content)
          end

          # The completing write scrubs the snapshotted notice address, so read
          # it first. The user's own email is erased by this deletion and is
          # never the source (IMP-b719328ddeb9).
          address = @deletion_request.notification_email

          @deletion_request.update!(
            status: "completed",
            completed_at: Time.current,
            deletion_log: params[:deletion_log] || []
          )
          log_internal_audit("data_deletion.complete", "DeletionRequest", @deletion_request.id,
                             account_id: @deletion_request.account_id)

          send_completion_notification(address)

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion completed"
          )
        end

        # A missing address (a legacy row, or a user who had none) is a warning,
        # never a failure: the erasure this request records has already happened.
        def send_completion_notification(address)
          if address.blank?
            Rails.logger.warn "[DataDeletionRequests] #{@deletion_request.id}: no notification address " \
                              "on file, skipping the completion notification"
            return
          end

          NotificationService.send_email(
            template: "data_deletion_completed",
            email: address,
            data: {
              request_id: @deletion_request.id,
              completed_at: @deletion_request.completed_at.iso8601
            }
          )
        end

        def serialize_request(request, include_details: false)
          data = {
            id: request.id,
            deletion_type: request.deletion_type,
            status: request.status,
            account_id: request.account_id,
            user_id: request.user_id,
            data_types_to_delete: request.data_types_to_delete,
            data_types_to_retain: request.data_types_to_retain,
            created_at: request.created_at
          }

          if include_details
            data[:reason] = request.reason
            data[:approved_at] = request.approved_at
            data[:processed_by_id] = request.processed_by_id
            data[:rejection_reason] = request.rejection_reason
            data[:processing_started_at] = request.processing_started_at
            data[:completed_at] = request.completed_at
            data[:grace_period_ends_at] = request.grace_period_ends_at
            data[:deletion_log] = request.deletion_log
            data[:retention_log] = request.retention_log
            data[:error_message] = request.error_message
            data[:metadata] = request.metadata
            # The one place the snapshotted notice address leaves the server
            # (IMP-b719328ddeb9): the worker's completion notice needs it, read
            # here BEFORE the completing write scrubs it. Only the detail
            # (show) shape carries it; every write response omits it.
            data[:notification_email] = request.notification_email
          end

          data
        end
      end
    end
  end
end
