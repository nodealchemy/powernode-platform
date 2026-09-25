# frozen_string_literal: true

module Api
  module V1
    module Internal
      class DataExportRequestsController < InternalBaseController
        before_action :set_export_request, only: [ :show, :update ]

        # GET /api/v1/internal/data_export_requests/:id
        def show
          render_success({ data_export_request: serialize_request(@export_request, include_details: true) })
        end

        # POST /api/v1/internal/data_export_requests
        def create
          @export_request = DataManagement::ExportRequest.new(export_request_params)
          @export_request.status = "pending"

          if @export_request.save
            # Queue processing through the worker HTTP API seam
            queue_worker_export_job(@export_request.id)

            render_success({ data_export_request: serialize_request(@export_request) }, status: :created)
          else
            render_error(@export_request.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/internal/data_export_requests/:id
        def update
          case params[:action_type]
          when "start"
            start_export
          when "complete"
            complete_export
          when "fail"
            fail_export
          when "expire"
            expire_export
          when "retry"
            retry_export
          else
            if @export_request.update(export_request_update_params)
              render_success({ data_export_request: serialize_request(@export_request) })
            else
              render_error(@export_request.errors.full_messages.join(", "), status: :unprocessable_content)
            end
          end
        end

        private

        # Dispatch export processing through the worker HTTP API seam. The old
        # DataManagement::Export{Processing,Execution}Job classes never existed
        # (server or worker) and the server runs no Sidekiq/ActiveJob backend,
        # so enqueuing them raised NameError (500). Compliance::DataExportJob is
        # the worker job that processes DataManagement::ExportRequest records.
        def queue_worker_export_job(export_request_id)
          WorkerApiClient.new.queue_job("Compliance::DataExportJob", [ export_request_id ], queue: "compliance")
        rescue WorkerApiClient::ApiError => e
          Rails.logger.error "[DataExportRequests] Failed to queue Compliance::DataExportJob " \
                             "for #{export_request_id}: #{e.message}"
        end

        def set_export_request
          @export_request = DataManagement::ExportRequest.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data export request not found", status: :not_found)
        end

        def export_request_params
          params.require(:data_export_request).permit(
            :account_id, :user_id, :format, :export_type,
            include_data_types: [], exclude_data_types: [], metadata: {}
          )
        end

        def export_request_update_params
          params.require(:data_export_request).permit(metadata: {})
        end

        def start_export
          unless @export_request.pending?
            return render_error("Export is not pending", status: :unprocessable_content)
          end

          @export_request.update!(
            status: "processing",
            processing_started_at: Time.current
          )

          # Execute export in background through the worker HTTP API seam
          queue_worker_export_job(@export_request.id)

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export started"
          )
        end

        def complete_export
          unless @export_request.processing?
            return render_error("Export is not processing", status: :unprocessable_content)
          end

          @export_request.update!(
            status: "completed",
            completed_at: Time.current,
            file_path: params[:file_path],
            file_size_bytes: params[:file_size_bytes],
            download_token: SecureRandom.urlsafe_base64(32),
            download_token_expires_at: 7.days.from_now,
            expires_at: 30.days.from_now
          )

          # Send completion notification with download link
          NotificationService.send_email(
            template: "data_export_ready",
            user_id: @export_request.user_id,
            data: {
              request_id: @export_request.id,
              expires_at: @export_request.expires_at&.iso8601,
              file_size: ActionController::Base.helpers.number_to_human_size(@export_request.file_size_bytes)
            }
          )

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export completed"
          )
        end

        def fail_export
          unless @export_request.processing?
            return render_error("Export is not processing", status: :unprocessable_content)
          end

          # IMP-0310a1351dab review round 4, item 4 (LOW, but introduced by
          # this fix's own bounded retry): this action is now reachable up
          # to EXPORT_DELIVERY_RETRY_LIMIT + 1 times for the SAME export
          # (Compliance::AccountTerminationJob's handle_failed_export!/
          # handle_stale_processing_export! reset-and-retry loop routes every
          # subsequent failure back through this same action) — captured
          # BEFORE the update below, since `retry_export` is what increments
          # `delivery_retry_count`, and this action always runs strictly
          # AFTER whichever retry preceded it.
          first_failure = (@export_request.metadata || {})["delivery_retry_count"].to_i.zero?

          @export_request.update!(
            status: "failed",
            error_message: params[:error_message],
            completed_at: Time.current
          )

          # Only the FIRST failure notifies the user — from their side this
          # is still one outstanding request; up to EXPORT_DELIVERY_RETRY_LIMIT
          # additional "your export failed" emails while this job retries
          # internally would be noise, not a status update they can act on.
          if first_failure
            NotificationService.send_email(
              template: "data_export_failed",
              user_id: @export_request.user_id,
              data: {
                request_id: @export_request.id,
                error: "We encountered an issue generating your data export. Please try again or contact support."
              }
            )
          end

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export marked as failed"
          )
        end

        # IMP-0310a1351dab review round 2, item 6 (operator ruling 2026-09-24):
        # a 'failed' export is never treated as delivered-for-deletion — it
        # has delivered nothing. Compliance::AccountTerminationJob resets it
        # back to 'pending' and re-queues Compliance::DataExportJob through
        # this action, up to its own bounded attempt count (tracked in
        # metadata, read back off this same response so the worker's retry
        # limit survives worker restarts and reruns across sweeps rather
        # than being counted in-process). error_message/processing_started_at
        # are cleared so a stale error/timestamp from the prior attempt does
        # not leak into the retried run.
        def retry_export
          unless @export_request.failed?
            return render_error("Export is not failed", status: :unprocessable_content)
          end

          retry_count = (@export_request.metadata || {})["delivery_retry_count"].to_i + 1

          @export_request.update!(
            status: "pending",
            error_message: nil,
            processing_started_at: nil,
            metadata: (@export_request.metadata || {}).merge("delivery_retry_count" => retry_count)
          )

          # include_details: true (unlike the other action_type branches
          # above) so the caller can read `metadata.delivery_retry_count`
          # back off this same response, rather than needing a second GET
          # just to learn the attempt count it just wrote.
          render_success(
            { data_export_request: serialize_request(@export_request, include_details: true) },
            message: "Export reset for retry (attempt #{retry_count})"
          )
        end

        def expire_export
          unless @export_request.completed?
            return render_error("Export is not completed", status: :unprocessable_content)
          end

          # Delete the exported file
          if @export_request.file_path.present?
            begin
              FileUtils.rm_rf(@export_request.file_path)
            rescue StandardError => e
              Rails.logger.warn "Failed to delete export file: #{e.message}"
            end
          end

          @export_request.update!(
            status: "expired",
            download_token: nil,
            download_token_expires_at: nil
          )

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export expired"
          )
        end

        def serialize_request(request, include_details: false)
          data = {
            id: request.id,
            status: request.status,
            account_id: request.account_id,
            user_id: request.user_id,
            format: request.format,
            export_type: request.export_type,
            include_data_types: request.include_data_types,
            exclude_data_types: request.exclude_data_types,
            created_at: request.created_at
          }

          if include_details
            data[:processing_started_at] = request.processing_started_at
            data[:completed_at] = request.completed_at
            data[:expires_at] = request.expires_at
            data[:file_path] = request.file_path
            data[:file_size_bytes] = request.file_size_bytes
            data[:error_message] = request.error_message
            data[:metadata] = request.metadata
            # IMP-0310a1351dab: the ONE field the worker's pre-deletion gate
            # (Compliance::AccountTerminationJob#export_ready_for_deletion?)
            # reads to decide whether it may proceed — computed from
            # DataManagement::ExportRequest#delivered_for_deletion?, the
            # single place that policy lives (operator ruling 2026-09-24:
            # delivered = downloaded, or download window elapsed unused).
            # The worker does not (and must not) re-derive that rule itself.
            data[:delivered_for_deletion] = request.delivered_for_deletion?
          end

          data
        end
      end
    end
  end
end
