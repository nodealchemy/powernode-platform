# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class SelfHealingController < InternalBaseController
          # POST /api/v1/internal/ai/self_healing/check_stuck_workflows
          def check_stuck_workflows
            cutoff = 30.minutes.ago
            stuck = ::Ai::WorkflowRun.where(status: "running")
                                      .where("started_at < ?", cutoff)

            stuck.find_each do |run|
              run.update!(status: "failed", error_message: "Timed out after 30 minutes",
                          completed_at: Time.current)
              Rails.logger.warn "[SelfHealing] Cancelled stuck workflow run #{run.id}"
            end

            render_success(count: stuck.count)
          end

          # POST /api/v1/internal/ai/self_healing/check_degraded_providers
          def check_degraded_providers
            degraded = []
            ::Ai::Provider.active.find_each do |provider|
              # Check recent error rate from executions
              recent = ::Ai::AgentExecution.where(ai_provider_id: provider.id)
                                           .where("created_at > ?", 1.hour.ago)
              total = recent.count
              failed = recent.where(status: "failed").count
              next if total < 5

              error_rate = (failed.to_f / total * 100).round(1)
              if error_rate > 50
                degraded << { provider_id: provider.id, name: provider.name,
                              error_rate: error_rate, total: total, failed: failed }
                Rails.logger.warn "[SelfHealing] Provider #{provider.name} degraded: #{error_rate}% error rate"
              end
            end

            render_success(degraded_providers: degraded, count: degraded.size)
          end

          # POST /api/v1/internal/ai/self_healing/check_orphaned_executions
          def check_orphaned_executions
            cutoff = 2.hours.ago
            orphaned = ::Ai::AgentExecution.where(status: "running")
                                            .where("started_at < ?", cutoff)

            orphaned.find_each do |execution|
              execution.update!(status: "failed",
                                error_message: "Orphaned execution timed out after 2 hours",
                                completed_at: Time.current)
              Rails.logger.warn "[SelfHealing] Cancelled orphaned execution #{execution.id}"
            end

            render_success(count: orphaned.count)
          end

          # POST /api/v1/internal/ai/self_healing/check_anomalies
          def check_anomalies
            anomalies = []

            # Check for accounts with unusual execution patterns
            ::Account.find_each do |account|
              recent_count = ::Ai::AgentExecution.where(account: account)
                                                  .where("created_at > ?", 1.hour.ago).count
              if recent_count > 100
                anomalies << { account_id: account.id, type: "high_execution_rate",
                               count: recent_count }
              end
            end

            render_success(anomalies: anomalies, count: anomalies.size)
          end
        end
      end
    end
  end
end
