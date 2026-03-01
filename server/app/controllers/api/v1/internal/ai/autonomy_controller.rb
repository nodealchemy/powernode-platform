# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class AutonomyController < InternalBaseController
          # GET /api/v1/internal/ai/observation_pipeline/accounts
          # Returns account IDs that have autonomous agents needing observation collection
          def observation_accounts
            account_ids = ::Ai::RalphLoop
              .where(scheduling_mode: "autonomous", schedule_paused: false)
              .where(status: %w[pending running paused])
              .distinct
              .pluck(:account_id)

            render_success(account_ids)
          end

          # POST /api/v1/internal/ai/observation_pipeline/run
          # Run observation pipeline for a specific account
          def run_observation_pipeline
            account = Account.find(params[:account_id])

            if account.ai_suspended?
              return render_success(agents_processed: 0, observations_created: 0, skipped: "ai_suspended")
            end

            result = ::Ai::Autonomy::ObservationPipelineService.run_for_account(account)
            render_success(result)
          end

          # POST /api/v1/internal/ai/goals/maintenance
          # Auto-abandon stale goals across all accounts
          def goals_maintenance
            goals_abandoned = 0

            ::Ai::AgentGoal.stale.find_each do |goal|
              goal.abandon!("Auto-abandoned: no progress for #{::Ai::AgentGoal::STALE_DAYS} days")
              goals_abandoned += 1
            rescue StandardError => e
              Rails.logger.error "[GoalMaintenance] Failed to abandon goal #{goal.id}: #{e.message}"
            end

            render_success(goals_abandoned: goals_abandoned)
          end

          # POST /api/v1/internal/ai/escalations/auto_escalate
          # Auto-escalate overdue escalations across all accounts
          def auto_escalate_escalations
            escalated_count = 0

            Account.active.find_each do |account|
              next if account.ai_suspended?

              service = ::Ai::EscalationService.new(account: account)
              escalated_count += service.auto_escalate_overdue!
            rescue StandardError => e
              Rails.logger.error "[AutoEscalate] Failed for account #{account.id}: #{e.message}"
            end

            render_success(escalated_count: escalated_count)
          end

          # POST /api/v1/internal/ai/proposals/expire_overdue
          # Expire overdue proposals across all accounts
          def expire_overdue_proposals
            expired_count = 0

            Account.active.find_each do |account|
              service = ::Ai::ProposalService.new(account: account)
              expired_count += service.expire_overdue!
            rescue StandardError => e
              Rails.logger.error "[ProposalExpiry] Failed for account #{account.id}: #{e.message}"
            end

            render_success(expired_count: expired_count)
          end

          # POST /api/v1/internal/ai/observations/cleanup
          # Delete expired and old processed observations
          def observations_cleanup
            # Delete expired observations
            expired_deleted = ::Ai::AgentObservation
              .where("expires_at IS NOT NULL AND expires_at < ?", Time.current)
              .delete_all

            # Delete old processed observations (> 7 days)
            processed_deleted = ::Ai::AgentObservation
              .where(processed: true)
              .where("created_at < ?", 7.days.ago)
              .delete_all

            render_success(
              expired_deleted: expired_deleted,
              processed_deleted: processed_deleted
            )
          end

          # POST /api/v1/internal/ai/intervention_policies/analyze_patterns
          # Analyze approval patterns and suggest policy adjustments
          def analyze_policy_patterns
            suggestions_count = 0

            Account.active.find_each do |account|
              service = ::Ai::FeedbackLoopService.new(account: account)

              # Analyze patterns for each active autonomous agent
              account.ai_agents.where(status: "active").find_each do |agent|
                result = service.analyze_patterns(agent: agent)
                next unless result

                result[:suggestions].each do |suggestion|
                  # Create an improvement recommendation for each suggestion
                  ::Ai::ImprovementRecommendation.create(
                    account_id: account.id,
                    ai_agent_id: agent.id,
                    title: suggestion[:message],
                    recommendation_type: suggestion[:type],
                    priority: suggestion[:type] == "quality_concern" ? "high" : "medium",
                    description: "Based on #{result[:total_proposals]} proposals with #{(result[:approval_rate] * 100).round(1)}% approval rate",
                    status: "pending"
                  )
                  suggestions_count += 1
                rescue StandardError => e
                  Rails.logger.warn "[PolicyTuning] Failed to create suggestion: #{e.message}"
                end
              end
            rescue StandardError => e
              Rails.logger.error "[PolicyTuning] Failed for account #{account.id}: #{e.message}"
            end

            render_success(suggestions_count: suggestions_count)
          end
        end
      end
    end
  end
end
