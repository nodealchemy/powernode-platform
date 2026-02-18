# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SkillGraphController < ApplicationController
        before_action :authenticate_request

        # GET /api/v1/ai/skill_graph/subgraph
        def subgraph
          authorize_permission!("ai.skills.read")
          result = bridge_service.skill_subgraph
          render_success(result)
        end

        # POST /api/v1/ai/skill_graph/sync
        def sync
          authorize_permission!("ai.skills.update")
          result = bridge_service.sync_all_skills
          render_success(result)
        end

        # POST /api/v1/ai/skill_graph/discover
        def discover
          authorize_permission!("ai.skills.read")
          task_context = params[:task_context]
          return render_error("task_context required", status: :bad_request) if task_context.blank?

          result = traversal_service.traverse(
            task_context: task_context,
            mode: params[:mode] || :auto,
            token_budget: params[:token_budget]&.to_i || 2000
          )
          render_success(result)
        end

        # POST /api/v1/ai/skill_graph/edges
        def create_edge
          authorize_permission!("ai.knowledge_graph.manage")

          edge = bridge_service.create_skill_edge(
            source_skill_id: params[:source_skill_id],
            target_skill_id: params[:target_skill_id],
            relation_type: params[:relation_type],
            weight: params[:weight]&.to_f || 1.0,
            confidence: params[:confidence]&.to_f || 1.0
          )
          render_success(edge: serialize_edge(edge))
        rescue ArgumentError, ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/skill_graph/edges/:id
        def update_edge
          authorize_permission!("ai.knowledge_graph.manage")

          edge = current_account.ai_knowledge_graph_edges.find(params[:id])
          update_attrs = {}
          update_attrs[:weight] = params[:weight].to_f if params[:weight].present?
          update_attrs[:confidence] = params[:confidence].to_f if params[:confidence].present?

          edge.update!(update_attrs) if update_attrs.any?
          render_success(edge: serialize_edge(edge))
        rescue ActiveRecord::RecordNotFound
          render_error("Edge not found", status: :not_found)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/skill_graph/edges/:id
        def destroy_edge
          authorize_permission!("ai.knowledge_graph.manage")
          bridge_service.remove_skill_edge(params[:id])
          render_success(deleted: true)
        rescue ::Ai::KnowledgeGraph::GraphServiceError => e
          render_error(e.message, status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/auto_detect
        def auto_detect
          authorize_permission!("ai.skills.read")
          skill = ::Ai::Skill.for_account(current_account.id).find(params[:skill_id])
          threshold = params[:similarity_threshold]&.to_f || 0.7

          suggestions = bridge_service.auto_detect_relationships(skill, similarity_threshold: threshold)
          render_success(suggestions: suggestions, count: suggestions.size)
        rescue ActiveRecord::RecordNotFound
          render_error("Skill not found", status: :not_found)
        end

        # GET /api/v1/ai/skill_graph/team_coverage/:team_id
        def team_coverage
          authorize_permission!("ai.teams.manage")
          team = current_account.ai_agent_teams.find(params[:team_id])

          result = coverage_service.analyze_coverage(team)
          render_success(result)
        rescue ActiveRecord::RecordNotFound
          render_error("Team not found", status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/team_gaps/:team_id
        def team_gaps
          authorize_permission!("ai.teams.manage")
          team = current_account.ai_agent_teams.find(params[:team_id])
          task_context = params[:task_context]
          return render_error("task_context required", status: :bad_request) if task_context.blank?

          result = coverage_service.find_task_gaps(team, task_context: task_context)
          render_success(result)
        rescue ActiveRecord::RecordNotFound
          render_error("Team not found", status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/suggest_agents/:team_id
        def suggest_agents
          authorize_permission!("ai.teams.manage")
          team = current_account.ai_agent_teams.find(params[:team_id])
          task_context = params[:task_context]
          return render_error("task_context required", status: :bad_request) if task_context.blank?

          result = coverage_service.suggest_agents_for_gaps(team, task_context: task_context)
          render_success(result)
        rescue ActiveRecord::RecordNotFound
          render_error("Team not found", status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/compose_team
        def compose_team
          authorize_permission!("ai.teams.manage")
          task_context = params[:task_context]
          return render_error("task_context required", status: :bad_request) if task_context.blank?

          result = coverage_service.compose_team_suggestion(
            task_context: task_context,
            max_members: params[:max_members]&.to_i || 5
          )
          render_success(result)
        end

        # GET /api/v1/ai/skill_graph/agent_context/:agent_id
        def agent_context
          authorize_permission!("ai.skills.read")
          agent = current_account.ai_agents.find(params[:agent_id])

          result = enrichment_service.enrich(
            agent: agent,
            input_text: params[:input_text] || "",
            mode: params[:mode] || :manifest,
            token_budget: params[:token_budget]&.to_i || 2000
          )
          render_success(result)
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        private

        def authorize_permission!(permission)
          return if current_user.has_permission?(permission)

          render_error("Forbidden", status: :forbidden)
        end

        def bridge_service
          @bridge_service ||= ::Ai::SkillGraph::BridgeService.new(current_account)
        end

        def traversal_service
          @traversal_service ||= ::Ai::SkillGraph::TraversalService.new(current_account)
        end

        def coverage_service
          @coverage_service ||= ::Ai::SkillGraph::TeamCoverageService.new(current_account)
        end

        def enrichment_service
          @enrichment_service ||= ::Ai::SkillGraph::ContextEnrichmentService.new(current_account)
        end

        def serialize_edge(edge)
          {
            id: edge.id,
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            relation_type: edge.relation_type,
            weight: edge.weight,
            confidence: edge.confidence,
            created_at: edge.created_at
          }
        end
      end
    end
  end
end
