# frozen_string_literal: true

module Ai
  module Tools
    # Entry point for multi-modal content generation: starts a content_production
    # Ai::Mission (brief → script → asset_generation → composition → render →
    # deliver) together with the FileManagement::Bundle that holds its assets, so
    # agents/operators can kick off a production. Mirrors ImageGenerationTool.
    #
    # Scenes are produced on the existing pipeline (image generation + ffmpeg
    # stitching, Prawn documents); paid external video/audio provider generation
    # is intentionally NOT exposed here (parked pending a provider/credential
    # decision) — this tool drives the credential-free path end to end.
    class ContentProductionMissionTool < BaseTool
      REQUIRED_PERMISSION = "ai.missions.manage"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "content_production_status", mutating: false
      declare_action "start_content_production", mutating: true

      def self.definition
        {
          name: "content_production",
          description: "Start and monitor content_production missions (images, scene-stitched video, PDFs). " \
                       "Actions: start_content_production, content_production_status",
          parameters: {
            action: { type: "string", required: true, description: "Action: start_content_production, content_production_status" },
            name: { type: "string", required: false, description: "Production name (required for start_content_production)" },
            bundle_type: { type: "string", required: false, description: "video_project, document, image_album, audio_album, mixed (default: video_project)" },
            brief: { type: "object", required: false, description: "Content brief: goal, format, audience, constraints" },
            mission_id: { type: "string", required: false, description: "Mission id (required for content_production_status)" }
          }
        }
      end

      def self.action_definitions
        {
          "start_content_production" => {
            description: "Create and start a content_production mission plus its asset bundle. Returns the mission + bundle.",
            parameters: {
              name: { type: "string", required: true, description: "Production name" },
              bundle_type: { type: "string", required: false, description: "video_project, document, image_album, audio_album, mixed (default: video_project)" },
              brief: { type: "object", required: false, description: "Content brief: goal, format, audience, constraints" }
            }
          },
          "content_production_status" => {
            description: "Get the status and current phase of a content_production mission.",
            parameters: {
              mission_id: { type: "string", required: true, description: "The content_production mission id" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "start_content_production" then start_content_production(params)
        when "content_production_status" then content_production_status(params)
        else
          {
            success: false,
            error: "Unknown action: #{params[:action]}. Valid actions: start_content_production, content_production_status"
          }
        end
      end

      private

      def start_content_production(params)
        return { success: false, error: "user context is required to start a content production" } unless user
        return { success: false, error: "name is required" } if params[:name].blank?

        bundle_type = params[:bundle_type].presence || "video_project"
        unless FileManagement::Bundle::BUNDLE_TYPES.include?(bundle_type)
          return { success: false, error: "invalid bundle_type: #{bundle_type}" }
        end

        mission = account.ai_missions.create!(
          name: params[:name],
          mission_type: "content_production",
          status: "draft",
          created_by: user,
          configuration: { "brief" => params[:brief] }.compact
        )

        bundle = FileManagement::Bundle.create!(
          account: account,
          created_by: user,
          mission: mission,
          name: params[:name],
          bundle_type: bundle_type,
          status: "draft"
        )

        Ai::Missions::OrchestratorService.new(mission: mission).start!

        {
          success: true,
          mission: mission.reload.mission_summary,
          bundle: bundle.bundle_summary
        }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      rescue Ai::Missions::OrchestratorService::OrchestrationError => e
        { success: false, error: e.message }
      end

      def content_production_status(params)
        return { success: false, error: "mission_id is required" } if params[:mission_id].blank?

        mission = account.ai_missions.find_by(id: params[:mission_id], mission_type: "content_production")
        return { success: false, error: "content_production mission not found" } unless mission

        { success: true, mission: mission.mission_summary }
      rescue StandardError => e
        { success: false, error: e.message }
      end
    end
  end
end
