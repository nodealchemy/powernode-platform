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

          # GET /api/v1/internal/ai/closure_driver/accounts
          # Accounts worth an OODA closure tick (IMP-e041c835a40d). Empty when
          # the driver is disabled — keeps the worker cron dumb and cheap: it
          # ticks every 15 min regardless, and this is where "off" is decided.
          def closure_accounts
            return render_success([]) unless ::Ai::Autonomy::ClosureDriverService.enabled?

            render_success(::Ai::AgentGoal.where(status: "active").distinct.pluck(:account_id))
          end

          # POST /api/v1/internal/ai/closure_driver/run
          # One closure-driver tick for one account. The service enforces the
          # activation gates itself (cadence flag, kill switch, control-plane
          # fence, budgets) — this endpoint just invokes and reports.
          def run_closure_driver
            account = Account.find(params[:account_id])
            render_success(::Ai::Autonomy::ClosureDriverService.new(account: account).run)
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

          # POST /api/v1/internal/ai/approval_requests/expire_overdue
          # Expire overdue approval requests across all accounts. Previously no
          # cron drove ApprovalRequest expiry, so requests on the canonical seam
          # (deferred-ops, campaign lands) silently never timed out.
          def expire_overdue_approval_requests
            expired_count = 0

            Account.active.find_each do |account|
              service = ::Ai::Autonomy::ApprovalWorkflowService.new(account: account)
              expired_count += service.expire_overdue!
            rescue StandardError => e
              Rails.logger.error "[ApprovalRequestExpiry] Failed for account #{account.id}: #{e.message}"
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
                  upsert_policy_suggestion!(account: account, agent: agent, suggestion: suggestion, result: result)
                  suggestions_count += 1
                rescue StandardError => e
                  Rails.logger.warn "[PolicyTuning] Failed to create suggestion: #{e.class}: #{e.message}"
                end
              end
            rescue StandardError => e
              Rails.logger.error "[PolicyTuning] Failed for account #{account.id}: #{e.message}"
            end

            render_success(suggestions_count: suggestions_count)
          end

          private

          POLICY_TUNING_SOURCE = "policy_tuning"

          # One standing offer per agent, refreshed in place. This endpoint runs on
          # a schedule over a rolling 30-day window, so creating unconditionally
          # would accrue a new pending row every run. The agent is carried by the
          # polymorphic target and the suggestion's own shape (message/priority/
          # type) rides in evidence, matching how Ai::Tools::ImprovementTool
          # #create_improvement maps rich fields.
          #
          # evidence["source"] identifies this writer. Ai::Learning::Improvement
          # Recommender produces agent_reliability rows against the same
          # (account, Ai::Agent, agent) tuple from a different signal; the tag is
          # what keeps the two from dedupe-matching and overwriting each other.
          def upsert_policy_suggestion!(account:, agent:, suggestion:, result:)
            attrs = {
              confidence_score: policy_suggestion_confidence(suggestion),
              evidence: {
                "title" => suggestion[:message],
                "description" => "Based on #{result[:total_proposals]} proposals with #{(result[:approval_rate] * 100).round(1)}% approval rate",
                "priority" => suggestion[:type] == "quality_concern" ? "high" : "medium",
                "suggestion_type" => suggestion[:type],
                "approval_rate" => result[:approval_rate],
                "total_proposals" => result[:total_proposals],
                "source" => POLICY_TUNING_SOURCE
              }
            }

            existing = open_policy_suggestion(account: account, agent: agent)
            return existing.update!(attrs) if existing

            ::Ai::ImprovementRecommendation.create!(
              attrs.merge(
                account_id: account.id,
                recommendation_type: "agent_reliability",
                target_type: "Ai::Agent",
                target_id: agent.id,
                status: "pending"
              )
            )
          end

          def open_policy_suggestion(account:, agent:)
            ::Ai::ImprovementRecommendation
              .where(account_id: account.id, recommendation_type: "agent_reliability",
                     target_type: "Ai::Agent", target_id: agent.id, status: "pending")
              .where("evidence->>'source' = ?", POLICY_TUNING_SOURCE)
              .first
          end

          # Confidence that the suggestion is correct, not a restatement of its
          # high/medium priority label (which rides in evidence): how consistently
          # the observed approval rate points the way the suggestion does.
          def policy_suggestion_confidence(suggestion)
            rate = suggestion[:approval_rate].to_f
            (suggestion[:type] == "quality_concern" ? 1.0 - rate : rate).clamp(0.0, 1.0)
          end
        end
      end
    end
  end
end
