# frozen_string_literal: true

module Ai
  # Transcribes an audio Chat::MessageAttachment. Resolves one of the account's
  # active AI provider credentials whose provider declares the
  # `audio_transcription` capability, builds its LLM adapter, and (when the
  # adapter supports transcription, e.g. OpenAI/-compatible) uploads the audio
  # and returns the transcript.
  #
  # No capable provider / no resolvable transcription model / no audio bytes →
  # graceful no-op (Result#ok? == false with a reason). The transcription model
  # is resolved FROM the provider (metadata override → a supported_models entry
  # tagged audio_transcription) — never hard-coded — per the platform's
  # resolve-models-from-providers rule.
  class AudioTranscriptionService
    Result = Struct.new(:ok?, :text, :reason, keyword_init: true)

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      return Result.new(ok?: false, reason: "not_audio") unless @attachment.audio?
      return Result.new(ok?: false, reason: "already_transcribed") if @attachment.transcription.present?

      credential = resolve_credential
      return Result.new(ok?: false, reason: "no_transcription_provider") unless credential

      adapter = ::Ai::Llm::AdapterFactory.build(provider: credential.provider, credential: credential)
      unless adapter.respond_to?(:transcribe)
        return Result.new(ok?: false, reason: "transcription_not_supported")
      end

      model = resolve_model(credential.provider)
      return Result.new(ok?: false, reason: "no_transcription_model") if model.blank?

      bytes = audio_bytes
      return Result.new(ok?: false, reason: "no_audio_content") if bytes.blank?

      text = adapter.transcribe(
        audio_bytes: bytes,
        filename: @attachment.filename.presence || "audio",
        content_type: @attachment.mime_type,
        model: model
      )

      text.present? ? Result.new(ok?: true, text: text) : Result.new(ok?: false, reason: "empty_transcription")
    rescue StandardError => e
      Rails.logger.error "[Ai::AudioTranscriptionService] #{e.class}: #{e.message}"
      Result.new(ok?: false, reason: "error")
    end

    private

    # First active account credential whose provider declares the
    # audio_transcription capability. Defensive — any resolution failure → nil.
    def resolve_credential
      account = @attachment.account
      return nil unless account.respond_to?(:ai_provider_credentials)

      account.ai_provider_credentials.active.includes(:provider).detect do |credential|
        credential.provider&.supports_capability?("audio_transcription")
      end
    rescue StandardError
      nil
    end

    # Resolve the transcription model FROM the provider (never hard-coded):
    # explicit metadata override first, then a supported_models entry tagged
    # with the audio_transcription capability.
    def resolve_model(provider)
      override = provider.metadata.is_a?(Hash) ? provider.metadata["transcription_model"] : nil
      return override if override.present?

      entry = Array(provider.supported_models).find do |model|
        model.is_a?(Hash) && Array(model["capabilities"]).include?("audio_transcription")
      end
      entry && (entry["id"] || entry["name"])
    end

    def audio_bytes
      @attachment.file_object&.read
    rescue StandardError => e
      Rails.logger.warn "[Ai::AudioTranscriptionService] could not read audio for ##{@attachment.id}: #{e.message}"
      nil
    end
  end
end
