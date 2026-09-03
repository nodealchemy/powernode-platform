# frozen_string_literal: true

module Ai
  module Tools
    # Generate speech/voiceover audio from text via the account's ElevenLabs
    # provider. Mirrors ImageGenerationTool. Real (billable) generation requires
    # an operator-configured ElevenLabs credential; shares the AI media-generation
    # permission with image generation.
    class AudioGenerationTool < BaseTool
      REQUIRED_PERMISSION = "ai.image.generate"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "generate_audio", mutating: true

      def self.definition
        {
          name: "audio_generation",
          description: "Generate speech/voiceover audio from text using the account's ElevenLabs provider. Action: generate_audio",
          parameters: {
            action: { type: "string", required: true, description: "Action: generate_audio" },
            text: { type: "string", required: false, description: "Text to synthesize into speech" },
            voice_id: { type: "string", required: false, description: "ElevenLabs voice id (defaults to provider/credential config)" },
            model: { type: "string", required: false, description: "ElevenLabs model (defaults to the provider's configured model)" },
            filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" }
          }
        }
      end

      def self.action_definitions
        {
          "generate_audio" => {
            description: "Synthesize speech/voiceover from text via ElevenLabs and store it as an ai_generated file.",
            parameters: {
              text: { type: "string", required: true, description: "Text to synthesize into speech" },
              voice_id: { type: "string", required: false, description: "ElevenLabs voice id (defaults to provider/credential config)" },
              model: { type: "string", required: false, description: "ElevenLabs model (defaults to provider config)" },
              filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "generate_audio" then generate_audio(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid actions: generate_audio" }
        end
      end

      private

      def generate_audio(params)
        return { success: false, error: "text is required" } if params[:text].blank?

        result = Ai::AudioGenerationService.new(account: account, user: user).generate(
          text: params[:text],
          voice_id: params[:voice_id],
          model: params[:model],
          filename: params[:filename]
        )

        response = { success: true, model: result[:model], voice_id: result[:voice_id], provider: result[:provider] }
        response[:file] = serialize_file(result[:file_object]) if result[:file_object]
        response
      rescue Ai::AudioGenerationService::GenerationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error "[AudioGenerationTool] Unexpected error: #{e.message}"
        { success: false, error: "Audio generation failed: #{e.message}" }
      end

      def serialize_file(file_obj)
        {
          id: file_obj.id,
          filename: file_obj.filename,
          content_type: file_obj.content_type,
          file_size: file_obj.file_size,
          category: file_obj.category,
          metadata: file_obj.metadata,
          created_at: file_obj.created_at&.iso8601
        }
      end
    end
  end
end
