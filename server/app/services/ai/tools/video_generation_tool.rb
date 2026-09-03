# frozen_string_literal: true

module Ai
  module Tools
    # Generate video from a text prompt via the account's Runway provider.
    # Mirrors ImageGenerationTool. Real (billable) generation requires an
    # operator-configured Runway credential; shares the AI media-generation
    # permission with image generation.
    class VideoGenerationTool < BaseTool
      REQUIRED_PERMISSION = "ai.image.generate"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "generate_video", mutating: true

      def self.definition
        {
          name: "video_generation",
          description: "Generate video from a text prompt using the account's Runway provider. Action: generate_video",
          parameters: {
            action: { type: "string", required: true, description: "Action: generate_video" },
            prompt: { type: "string", required: false, description: "Text description of the video to generate" },
            model: { type: "string", required: false, description: "Runway model (defaults to the provider's configured model)" },
            duration: { type: "integer", required: false, description: "Clip duration in seconds" },
            ratio: { type: "string", required: false, description: "Aspect ratio, e.g. 1280:768" },
            filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" }
          }
        }
      end

      def self.action_definitions
        {
          "generate_video" => {
            description: "Generate a video clip from a prompt via Runway and store it as an ai_generated file.",
            parameters: {
              prompt: { type: "string", required: true, description: "Text description of the video to generate" },
              model: { type: "string", required: false, description: "Runway model (defaults to provider config)" },
              duration: { type: "integer", required: false, description: "Clip duration in seconds" },
              ratio: { type: "string", required: false, description: "Aspect ratio, e.g. 1280:768" },
              filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "generate_video" then generate_video(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid actions: generate_video" }
        end
      end

      private

      def generate_video(params)
        return { success: false, error: "prompt is required" } if params[:prompt].blank?

        result = Ai::VideoGenerationService.new(account: account, user: user).generate(
          prompt: params[:prompt],
          model: params[:model],
          duration: params[:duration],
          ratio: params[:ratio],
          filename: params[:filename]
        )

        response = { success: true, model: result[:model], task_id: result[:task_id], provider: result[:provider] }
        response[:file] = serialize_file(result[:file_object]) if result[:file_object]
        response
      rescue Ai::VideoGenerationService::GenerationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error "[VideoGenerationTool] Unexpected error: #{e.message}"
        { success: false, error: "Video generation failed: #{e.message}" }
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
