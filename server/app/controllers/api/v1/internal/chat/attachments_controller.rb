# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Chat
        # Worker callbacks for the chat-attachment scan + transcription pipeline.
        # The standalone worker performs the ClamAV / off-request-path I/O and
        # calls these endpoints; all model/DB state stays on the server
        # (worker is API-only).
        #
        # Worker-receiver discipline: these are worker callbacks, so they MUST
        # NOT return 5xx on a processing error (a 500 would trigger Sidekiq retry
        # storms). On any error they log and return 2xx. They are idempotent —
        # each simply applies the latest reported outcome.
        class AttachmentsController < InternalBaseController
          # GET /api/v1/internal/chat/attachments/:id/scan_payload
          #
          # Tells the worker where to fetch the bytes — the worker pulls them via
          # the existing /api/v1/worker/files/:id/download path, so no bytes are
          # inlined here. Attachments with no resolvable file object are reported
          # not-scannable and left pending (fail-closed).
          def scan_payload
            attachment = ::Chat::MessageAttachment.find_by(id: params[:id])
            return render_success(found: false) unless attachment

            if attachment.file_object_id.blank?
              return render_success(found: true, scannable: false, reason: "no_file_object")
            end

            render_success(
              found: true,
              scannable: true,
              file_object_id: attachment.file_object_id,
              mime_type: attachment.mime_type,
              filename: attachment.filename
            )
          rescue StandardError => e
            Rails.logger.error "[Internal::Chat::Attachments#scan_payload] #{params[:id]}: #{e.message}"
            render_success(found: false, error: e.message)
          end

          # POST /api/v1/internal/chat/attachments/:id/scan_result
          # Body: { status: completed|skipped|error, malware_detected:, threat:, reason: }
          def scan_result
            attachment = ::Chat::MessageAttachment.find_by(id: params[:id])
            unless attachment
              return render_success(applied: false, reason: "attachment_not_found")
            end

            attachment.apply_scan_result(
              status: params[:status].to_s,
              malware_detected: ActiveModel::Type::Boolean.new.cast(params[:malware_detected]),
              threat: params[:threat].presence
            )

            render_success(
              applied: true,
              scanned: attachment.scanned_for_malware?,
              malware_detected: attachment.malware_detected?
            )
          rescue StandardError => e
            Rails.logger.error "[Internal::Chat::Attachments#scan_result] #{params[:id]}: #{e.message}"
            render_success(applied: false, error: e.message)
          end

          # POST /api/v1/internal/chat/attachments/:id/transcribe
          #
          # Runs the server transcription seam (Ai::AudioTranscriptionService),
          # which no-ops gracefully when no audio_transcription provider is
          # configured. When a provider IS wired, the transcript is persisted to
          # the attachment + message.
          def transcribe
            attachment = ::Chat::MessageAttachment.find_by(id: params[:id])
            unless attachment
              return render_success(transcribed: false, reason: "attachment_not_found")
            end

            result = ::Ai::AudioTranscriptionService.new(attachment).call
            if result.ok?
              attachment.set_transcription!(result.text)
              render_success(transcribed: true)
            else
              render_success(transcribed: false, reason: result.reason)
            end
          rescue StandardError => e
            Rails.logger.error "[Internal::Chat::Attachments#transcribe] #{params[:id]}: #{e.message}"
            render_success(transcribed: false, error: e.message)
          end
        end
      end
    end
  end
end
