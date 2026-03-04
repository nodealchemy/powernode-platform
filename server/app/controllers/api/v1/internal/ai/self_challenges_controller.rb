# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class SelfChallengesController < InternalBaseController
          # POST /api/v1/internal/ai/self_challenges/process
          # Called by AiSelfChallengeJob — execute, validate, and complete a challenge
          def process_challenge
            challenge = ::Ai::SelfChallenge.find(params[:challenge_id])
            account = challenge.account

            service = ::Ai::SelfImprovement::ChallengeService.new(account: account)

            service.execute_challenge!(challenge: challenge)
            service.validate_challenge!(challenge: challenge)
            service.complete_challenge!(challenge: challenge)

            render_success(
              challenge_id: challenge.id,
              status: challenge.reload.status,
              completed: true
            )
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          rescue StandardError => e
            Rails.logger.error "[SelfChallenge] Processing failed for challenge #{params[:challenge_id]}: #{e.message}"
            render_error("Challenge processing failed: #{e.message}", status: :unprocessable_content)
          end

          # POST /api/v1/internal/ai/self_challenges/schedule_daily
          # Called by AiSelfChallengeSchedulerJob — generate challenges for all active agents
          def schedule_daily
            challenges_created = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::SelfImprovement::ChallengeService.new(account: account)

              account.ai_agents.where(status: "active").find_each do |agent|
                difficulty = service.adaptive_difficulty(agent: agent)
                challenge = service.generate_challenge!(agent: agent, difficulty: difficulty)
                challenges_created += 1 if challenge
              rescue StandardError => e
                Rails.logger.error "[SelfChallenge] Scheduling failed for agent #{agent.id}: #{e.message}"
              end
            rescue StandardError => e
              Rails.logger.error "[SelfChallenge] Scheduling failed for account #{account.id}: #{e.message}"
            end

            render_success(challenges_created: challenges_created)
          end
        end
      end
    end
  end
end
