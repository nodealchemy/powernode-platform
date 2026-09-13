# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AgentIntelligenceController < ApplicationController
        before_action :validate_permissions
        before_action :set_agent

        # GET /api/v1/ai/agents/:agent_id/intelligence/summary
        def summary
          replays = current_account.ai_experience_replays.for_agent(@agent.id)

          # The `self_challenges` block was removed with the subsystem (D6).
          # Dropped from the payload rather than zeroed: a block of zeroes reads
          # as "this agent has run no challenges", which is a measurement, and
          # there is nothing left to measure.
          render_success(
            summary: {
              experience_replays: {
                total: replays.count,
                active: replays.active.count,
                avg_quality: replays.active.average(:quality_score)&.to_f&.round(3) || 0,
                avg_effectiveness: replays.active.average(:effectiveness_score)&.to_f&.round(3) || 0
              }
            }
          )
        end

        # GET /api/v1/ai/agents/:agent_id/intelligence/experience_replays
        def experience_replays
          scope = current_account.ai_experience_replays
            .for_agent(@agent.id)
            .includes(:source_execution)

          scope = scope.active if params[:status] == "active"
          scope = scope.few_shot if params[:few_shot] == "true"

          replays = scope.recent.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: replays.map { |r| serialize_replay(r) },
            total: replays.total_count,
            page: replays.current_page,
            per_page: replays.limit_value
          )
        end

        private

        def set_agent
          @agent = ::Ai::Agent.for_account(current_account.id).find(params[:agent_id])
        end

        def validate_permissions
          # require_permission is the canonical helper (Authentication concern);
          # authorize_permission! does not exist and raised NoMethodError (500)
          # on every agent_intelligence endpoint.
          require_permission("ai.manage")
        end

        def serialize_replay(replay)
          {
            id: replay.id,
            compressed_example: replay.compressed_example.truncate(500),
            status: replay.status,
            quality_score: replay.quality_score&.to_f,
            effectiveness_score: replay.effectiveness_score&.to_f,
            injection_count: replay.injection_count,
            positive_outcome_count: replay.positive_outcome_count,
            negative_outcome_count: replay.negative_outcome_count,
            last_injected_at: replay.last_injected_at&.iso8601,
            source_execution_id: replay.source_execution_id,
            created_at: replay.created_at.iso8601
          }
        end

      end
    end
  end
end
