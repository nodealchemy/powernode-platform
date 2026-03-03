# frozen_string_literal: true

module Ai
  module Tools
    class ImageGenerationTool < BaseTool
      REQUIRED_PERMISSION = "ai.image.generate"

      def self.definition
        {
          name: "image_generation",
          description: "Generate images using AI (DALL-E 3) and manage generated images. Actions: generate_image, list_generated_images",
          parameters: {
            action: { type: "string", required: true, description: "Action: generate_image, list_generated_images" },
            prompt: { type: "string", required: false, description: "Image description prompt" },
            size: { type: "string", required: false, description: "Image size: 1024x1024, 1024x1792, 1792x1024 (default: 1024x1024)" },
            quality: { type: "string", required: false, description: "Image quality: standard, hd (default: hd)" },
            style: { type: "string", required: false, description: "Image style: vivid, natural (default: vivid)" },
            model: { type: "string", required: false, description: "Model: dall-e-3 (default)" },
            filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" },
            limit: { type: "integer", required: false, description: "Max results for list (default: 20)" }
          }
        }
      end

      def self.action_definitions
        {
          "generate_image" => {
            description: "Generate an image using DALL-E 3 AI model. Returns the generated image file with metadata including the revised prompt.",
            parameters: {
              prompt: { type: "string", required: true, description: "Detailed description of the image to generate" },
              size: { type: "string", required: false, description: "Image size: 1024x1024, 1024x1792, 1792x1024 (default: 1024x1024)" },
              quality: { type: "string", required: false, description: "Image quality: standard, hd (default: hd)" },
              style: { type: "string", required: false, description: "Image style: vivid, natural (default: vivid)" },
              model: { type: "string", required: false, description: "Model: dall-e-3 (default: dall-e-3)" },
              filename: { type: "string", required: false, description: "Output filename (auto-generated if omitted)" }
            }
          },
          "list_generated_images" => {
            description: "List AI-generated images in the current account",
            parameters: {
              limit: { type: "integer", required: false, description: "Max results (default: 20)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "generate_image" then generate_image(params)
        when "list_generated_images" then list_generated_images(params)
        else
          {
            success: false,
            error: "Unknown action: #{params[:action]}. Valid actions: generate_image, list_generated_images"
          }
        end
      end

      private

      def generate_image(params)
        return { success: false, error: "prompt is required" } if params[:prompt].blank?

        service = Ai::ImageGenerationService.new(account: account)
        result = service.generate(
          prompt: params[:prompt],
          size: params[:size] || "1024x1024",
          quality: params[:quality] || "hd",
          style: params[:style] || "vivid",
          model: params[:model] || "dall-e-3",
          filename: params[:filename]
        )

        response = {
          success: true,
          revised_prompt: result[:revised_prompt],
          model: result[:model],
          size: result[:size],
          quality: result[:quality],
          style: result[:style]
        }

        if result[:file_object]
          response[:file] = serialize_file(result[:file_object])
        end

        response
      rescue Ai::ImageGenerationService::GenerationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error "[ImageGenerationTool] Unexpected error: #{e.message}"
        { success: false, error: "Image generation failed: #{e.message}" }
      end

      def list_generated_images(params)
        limit = (params[:limit] || 20).to_i.clamp(1, 100)

        images = FileManagement::Object
                   .where(account: account, category: "ai_generated")
                   .order(created_at: :desc)
                   .limit(limit)

        {
          success: true,
          count: images.size,
          images: images.map { |img| serialize_file(img) }
        }
      rescue StandardError => e
        { success: false, error: e.message }
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
