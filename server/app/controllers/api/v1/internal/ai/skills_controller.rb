# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class SkillsController < InternalBaseController
          # POST /api/v1/internal/ai/skills/seed_system
          def seed_system
            seed_file = Rails.root.join("db/seeds/ai_skills_seed.rb")

            unless File.exist?(seed_file)
              render_error("Skills seed file not found", status: :not_found)
              return
            end

            load seed_file
            render_success(message: "System skills seeded")
          rescue StandardError => e
            render_error("Failed to seed skills: #{e.message}", status: :unprocessable_content)
          end

          # POST /api/v1/internal/ai/skills/:id/record_usage
          def record_usage
            skill = ::Ai::Skill.find(params[:id])
            skill.increment_usage!
            render_success(usage_count: skill.usage_count)
          rescue ActiveRecord::RecordNotFound
            render_error("Skill not found", status: :not_found)
          end

          # POST /api/v1/internal/ai/skills/:id/refresh_connectors
          def refresh_connectors
            skill = ::Ai::Skill.find(params[:id])
            connectors = skill.skill_connectors.includes(:mcp_server)
            render_success(
              connectors: connectors.map { |c| { id: c.id, mcp_server_id: c.mcp_server_id, role: c.role } }
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Skill not found", status: :not_found)
          end
        end
      end
    end
  end
end
