# frozen_string_literal: true

module Ai
  # Generates speech/voiceover audio from text via a per-account ElevenLabs
  # provider. ElevenLabs' text-to-speech is synchronous: POST returns the audio
  # bytes directly. Base URL + model are resolved from the provider record; the
  # voice id comes from the call, the credential, or provider metadata — nothing
  # hardcoded. The result is stored as an ai_generated FileManagement::Object
  # (file_type audio).
  #
  # No real (billable) call happens without an operator-provided credential;
  # validate the endpoint/voice against the live API before production use.
  class AudioGenerationService
    include Ai::MediaGenerationCommon

    class GenerationError < StandardError; end

    PROVIDER_TYPE = "elevenlabs"
    DEFAULT_TTS_PATH = "/text-to-speech"

    attr_reader :account, :user

    def initialize(account:, user: nil)
      @account = account
      @user = user
    end

    # @return [Hash] :file_object (when store), :model, :voice_id, :provider
    def generate(text:, voice_id: nil, model: nil, filename: nil, store: true)
      raise GenerationError, "text is required" if text.to_s.strip.empty?

      provider, credential = resolve_provider_and_credential
      api_key = credential.credentials["api_key"]
      raise GenerationError, "No API key found for #{PROVIDER_TYPE} provider" if api_key.blank?

      base = provider.api_base_url.to_s.chomp("/")
      raise GenerationError, "#{PROVIDER_TYPE} provider has no api_base_url" if base.empty?

      voice_id ||= credential.credentials["voice_id"] || provider.metadata&.dig("default_voice_id")
      raise GenerationError, "No voice_id provided or configured for #{PROVIDER_TYPE} provider" if voice_id.blank?
      model ||= default_model(provider)

      bytes = synthesize(base, api_key, provider, text: text, voice_id: voice_id, model: model)

      result = { model: model, voice_id: voice_id, provider: provider.name }
      if store
        result[:file_object] = store_audio(bytes, filename: filename || generate_filename(text), text: text, model: model, voice_id: voice_id)
      else
        result[:audio_data] = bytes
      end
      result
    end

    private

    def synthesize(base, api_key, provider, text:, voice_id:, model:)
      path = provider.metadata&.dig("tts_path") || DEFAULT_TTS_PATH
      body = { text: text, model_id: model }

      resp = HTTP.headers(
        "xi-api-key" => api_key,
        "Content-Type" => "application/json",
        "Accept" => "audio/mpeg"
      ).timeout(120).post("#{base}#{path}/#{voice_id}", json: body)

      raise GenerationError, "ElevenLabs TTS failed: #{api_error(resp)}" unless resp.status.success?
      resp.body.to_s
    rescue HTTP::Error => e
      raise GenerationError, "HTTP request failed: #{e.message}"
    end

    def store_audio(bytes, filename:, text:, model:, voice_id:)
      store_generated_file(
        bytes,
        filename: filename,
        content_type: "audio/mpeg",
        metadata: {
          generator: PROVIDER_TYPE,
          model: model,
          voice_id: voice_id,
          text: text.to_s.truncate(2000)
        }
      )
    end

    def generate_filename(text)
      media_filename(text, prefix: "ai_voiceover", ext: "mp3")
    end
  end
end
