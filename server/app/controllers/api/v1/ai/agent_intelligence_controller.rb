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
          challenges = current_account.ai_self_challenges.for_agent(@agent.id)

          render_success(
            summary: {
              experience_replays: {
                total: replays.count,
                active: replays.active.count,
                avg_quality: replays.active.average(:quality_score)&.to_f&.round(3) || 0,
                avg_effectiveness: replays.active.average(:effectiveness_score)&.to_f&.round(3) || 0
              },
              self_challenges: {
                total: challenges.count,
                active: challenges.active.count,
                completed: challenges.completed.count,
                pass_rate: calculate_pass_rate(challenges)
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

        # GET /api/v1/ai/agents/:agent_id/intelligence/self_challenges
        def self_challenges
          scope = current_account.ai_self_challenges
            .for_agent(@agent.id)
            .includes(:skill, :executor_agent, :validator_agent)

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(difficulty: params[:difficulty]) if params[:difficulty].present?

          challenges = scope.recent.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: challenges.map { |c| serialize_challenge(c) },
            total: challenges.total_count,
            page: challenges.current_page,
            per_page: challenges.limit_value
          )
        end

        private

        def set_agent
          @agent = current_account.ai_agents.find(params[:agent_id])
        end

        def validate_permissions
          authorize_permission!("ai.manage")
        end

        def calculate_pass_rate(challenges)
          completed = challenges.completed
          return 0.0 if completed.empty?

          passed = completed.where("quality_score >= 0.7").count
          (passed.to_f / completed.count * 100).round(1)
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

        def serialize_challenge(challenge)
          {
            id: challenge.id,
            challenge_id: challenge.challenge_id,
            status: challenge.status,
            difficulty: challenge.difficulty,
            challenge_prompt: challenge.challenge_prompt&.truncate(300),
            expected_criteria: challenge.expected_criteria,
            response: challenge.response&.truncate(300),
            quality_score: challenge.quality_score&.to_f,
            validation_result: challenge.validation_result,
            skill: challenge.skill ? { id: challenge.skill.id, name: challenge.skill.name } : nil,
            executor_agent: challenge.executor_agent ? { id: challenge.executor_agent.id, name: challenge.executor_agent.name } : nil,
            validator_agent: challenge.validator_agent ? { id: challenge.validator_agent.id, name: challenge.validator_agent.name } : nil,
            created_at: challenge.created_at.iso8601
          }
        end
      end
    end
  end
end
