# frozen_string_literal: true

module Chat
  # Triggers server-side transcription of an audio Chat::MessageAttachment off
  # the synchronous request path.
  #
  # The actual transcription runs on the SERVER (it owns the AI providers); the
  # worker only moves it off the request path. The server transcription seam
  # (Ai::AudioTranscriptionService) no-ops gracefully when no provider declares
  # the audio_transcription capability, so today this job is a thin, retry-safe
  # trigger that becomes a real transcription the moment a provider is wired.
  class AttachmentTranscriptionJob < BaseJob
    sidekiq_options queue: "file_processing", retry: 2

    def execute(attachment_id)
      validate_required_params({ "attachment_id" => attachment_id }, "attachment_id")

      response = api_client.post(
        "/api/v1/internal/chat/attachments/#{attachment_id}/transcribe", {}
      )
      data = response["data"] || response
      log_info("Chat attachment transcription dispatched",
               attachment_id: attachment_id,
               transcribed: data.is_a?(Hash) ? data["transcribed"] : nil,
               reason: data.is_a?(Hash) ? data["reason"] : nil)
    end
  end
end
