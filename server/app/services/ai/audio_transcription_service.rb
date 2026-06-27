# frozen_string_literal: true

module Ai
  # Seam for transcribing an audio Chat::MessageAttachment. Resolves an AI
  # provider that declares the `audio_transcription` capability and delegates to
  # its #transcribe_audio.
  #
  # No provider implements the actual transcription call yet, so this currently
  # no-ops gracefully (Result#ok? == false, with a reason) rather than
  # fabricating a transcript. The moment a provider gains a
  # #transcribe_audio(attachment) method AND is tagged with the
  # audio_transcription capability, the resolve+delegate path below activates
  # with no other changes — that is the intended extension point.
  class AudioTranscriptionService
    Result = Struct.new(:ok?, :text, :reason, keyword_init: true)

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      return Result.new(ok?: false, reason: "not_audio") unless @attachment.audio?
      return Result.new(ok?: false, reason: "already_transcribed") if @attachment.transcription.present?

      provider = resolve_provider
      return Result.new(ok?: false, reason: "no_transcription_provider") unless provider
      unless provider.respond_to?(:transcribe_audio)
        return Result.new(ok?: false, reason: "transcription_not_implemented")
      end

      text = provider.transcribe_audio(@attachment)
      if text.present?
        Result.new(ok?: true, text: text)
      else
        Result.new(ok?: false, reason: "empty_transcription")
      end
    rescue StandardError => e
      Rails.logger.error "[Ai::AudioTranscriptionService] #{e.class}: #{e.message}"
      Result.new(ok?: false, reason: "error")
    end

    private

    # Account-scoped (plus any global) active providers declaring the
    # audio_transcription capability. Defensive: any resolution failure yields
    # nil → graceful no-op.
    def resolve_provider
      account = @attachment.account
      scope = ::Ai::Provider.where(account_id: [ account&.id, nil ].uniq)
      scope = scope.active if scope.respond_to?(:active)
      scope.detect { |provider| Array(provider.capabilities).include?("audio_transcription") }
    rescue StandardError
      nil
    end
  end
end
