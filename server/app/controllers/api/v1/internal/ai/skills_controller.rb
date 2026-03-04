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

          # POST /api/v1/internal/ai/skills/mutate
          # Called by AiSkillMutationJob — mutate a specific skill with a strategy
          def mutate
            skill = ::Ai::Skill.find(params[:skill_id])
            strategy = params[:strategy]

            valid_strategies = %w[learning_driven failure_analysis challenge_derived peer_comparison]
            unless valid_strategies.include?(strategy)
              return render_error("Invalid strategy. Must be one of: #{valid_strategies.join(', ')}", status: :unprocessable_content)
            end

            service = ::Ai::SelfImprovement::SkillMutationService.new(account: skill.account)
            version = service.mutate!(skill: skill, strategy: strategy)

            if version
              render_success(
                skill_id: skill.id,
                version_id: version.id,
                strategy: strategy,
                mutated: true
              )
            else
              render_success(mutated: false, reason: "mutation_skipped")
            end
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          rescue StandardError => e
            Rails.logger.error "[SkillMutation] Failed for skill #{params[:skill_id]}: #{e.message}"
            render_error("Mutation failed: #{e.message}", status: :unprocessable_content)
          end

          # POST /api/v1/internal/ai/skills/auto_evolve
          # Called by AiSkillAutoEvolutionJob — auto-mutate underperforming skills
          def auto_evolve
            threshold = (params[:threshold] || 0.4).to_f
            total_mutated = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::SelfImprovement::SkillMutationService.new(account: account)
              total_mutated += service.auto_mutate_underperforming!(threshold: threshold)
            rescue StandardError => e
              Rails.logger.error "[SkillAutoEvolve] Failed for account #{account.id}: #{e.message}"
            end

            render_success(mutated: total_mutated, threshold: threshold)
          end

          # POST /api/v1/internal/ai/skills/:id/refresh_connectors
          def refresh_connectors
            skill = ::Ai::Skill.find(params[:id])
            servers = skill.mcp_servers
            render_success(
              connectors: servers.map { |s| { id: s.id, name: s.name, status: s.status } }
            )
          rescue ActiveRecord::RecordNotFound
            render_error("Skill not found", status: :not_found)
          end
        end
      end
    end
  end
end
