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

        # ===================================================================
        # Lifecycle - Research & Proposals
        # ===================================================================

        # POST /api/v1/ai/skill_graph/research
        def research
          authorize_permission!("ai.skills.create")
          topic = params[:topic]
          return render_error("topic required", status: :bad_request) if topic.blank?

          sources = params[:sources] || %w[knowledge_graph knowledge_bases mcp]
          agent = params[:agent_id].present? ? current_account.ai_agents.find_by(id: params[:agent_id]) : nil

          result = research_service.research(topic: topic, sources: sources, requesting_agent: agent)
          render_success(result)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/skill_graph/proposals
        def list_proposals
          authorize_permission!("ai.skills.read")
          proposals = ::Ai::SkillProposal.where(account: current_account)
          proposals = proposals.by_status(params[:status]) if params[:status].present?
          proposals = proposals.order(created_at: :desc).limit(params[:limit]&.to_i || 50)
          render_success(proposals: proposals.map(&:proposal_summary))
        end

        # POST /api/v1/ai/skill_graph/proposals
        def create_proposal
          authorize_permission!("ai.skills.create")
          proposal = lifecycle_service.create_proposal(attributes: proposal_params)
          render_success(proposal: proposal.proposal_summary)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/skill_graph/proposals/:id
        def show_proposal
          authorize_permission!("ai.skills.read")
          proposal = current_account.ai_skill_proposals.find(params[:id])
          render_success(proposal: proposal.proposal_summary)
        rescue ActiveRecord::RecordNotFound
          render_error("Proposal not found", status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/proposals/:id/submit
        def submit_proposal
          authorize_permission!("ai.skills.create")
          proposal = lifecycle_service.submit_proposal(proposal_id: params[:id])
          render_success(proposal: proposal.proposal_summary)
        rescue ActiveRecord::RecordNotFound
          render_error("Proposal not found", status: :not_found)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/proposals/:id/approve
        def approve_proposal
          authorize_permission!("ai.skills.update")
          proposal = lifecycle_service.approve_proposal(proposal_id: params[:id], reviewer: current_user)
          render_success(proposal: proposal.proposal_summary)
        rescue ActiveRecord::RecordNotFound
          render_error("Proposal not found", status: :not_found)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/proposals/:id/reject
        def reject_proposal
          authorize_permission!("ai.skills.update")
          reason = params[:reason] || "No reason provided"
          proposal = lifecycle_service.reject_proposal(proposal_id: params[:id], reviewer: current_user, reason: reason)
          render_success(proposal: proposal.proposal_summary)
        rescue ActiveRecord::RecordNotFound
          render_error("Proposal not found", status: :not_found)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/proposals/:id/create_skill
        def create_skill_from_proposal
          authorize_permission!("ai.skills.create")
          result = lifecycle_service.create_skill_from_proposal(proposal_id: params[:id])
          render_success(skill: result[:skill].skill_summary, proposal: result[:proposal].proposal_summary)
        rescue ActiveRecord::RecordNotFound
          render_error("Proposal not found", status: :not_found)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # ===================================================================
        # Conflicts & Health
        # ===================================================================

        # GET /api/v1/ai/skill_graph/conflicts
        def conflicts
          authorize_permission!("ai.skills.read")
          conflicts = ::Ai::SkillConflict.where(account: current_account)
          conflicts = if params[:status].present?
                        conflicts.where(status: params[:status])
                      else
                        conflicts.active
                      end
          conflicts = conflicts.where(conflict_type: params[:type]) if params[:type].present?
          conflicts = conflicts.order(priority_score: :desc).limit(params[:limit]&.to_i || 50)
          render_success(conflicts: conflicts.map { |c| conflict_summary(c) })
        end

        # POST /api/v1/ai/skill_graph/conflicts/:id/resolve
        def resolve_conflict
          authorize_permission!("ai.knowledge_graph.manage")
          conflict = current_account.ai_skill_conflicts.find(params[:id])
          auto_repair_service.resolve_conflict(conflict, user: current_user)
          render_success(conflict: conflict_summary(conflict.reload))
        rescue ActiveRecord::RecordNotFound
          render_error("Conflict not found", status: :not_found)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/conflicts/:id/dismiss
        def dismiss_conflict
          authorize_permission!("ai.knowledge_graph.manage")
          conflict = current_account.ai_skill_conflicts.find(params[:id])
          conflict.dismiss!(user: current_user)
          render_success(conflict: conflict_summary(conflict.reload))
        rescue ActiveRecord::RecordNotFound
          render_error("Conflict not found", status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/scan
        def scan_conflicts
          authorize_permission!("ai.knowledge_graph.manage")
          result = conflict_detection_service.scan_all
          render_success(result)
        end

        # GET /api/v1/ai/skill_graph/health
        def health_score
          authorize_permission!("ai.skills.read")
          result = health_score_service.comprehensive_report
          render_success(result)
        end

        # ===================================================================
        # Evolution - Metrics, Versions & A/B Testing
        # ===================================================================

        # GET /api/v1/ai/skill_graph/skills/:skill_id/metrics
        def skill_metrics
          authorize_permission!("ai.skills.read")
          result = evolution_service.skill_metrics(skill_id: params[:skill_id])
          render_success(result)
        rescue StandardError => e
          render_error(e.message, status: :not_found)
        end

        # GET /api/v1/ai/skill_graph/skills/:skill_id/versions
        def version_history
          authorize_permission!("ai.skills.read")
          result = evolution_service.version_history(skill_id: params[:skill_id])
          render_success(versions: result)
        rescue StandardError => e
          render_error(e.message, status: :not_found)
        end

        # POST /api/v1/ai/skill_graph/skills/:skill_id/evolve
        def propose_evolution
          authorize_permission!("ai.skills.update")
          version = evolution_service.propose_evolution(skill_id: params[:skill_id])
          render_success(version: version.version_summary)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/versions/:id/activate
        def activate_version
          authorize_permission!("ai.skills.update")
          evolution_service.activate_version(version_id: params[:id])
          render_success(activated: true)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/skills/:skill_id/ab_test
        def start_ab_test
          authorize_permission!("ai.skills.update")
          result = evolution_service.start_ab_test(
            skill_id: params[:skill_id],
            variant_version_id: params[:variant_version_id],
            traffic_pct: params[:traffic_pct]&.to_f || 0.2
          )
          render_success(result)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/skills/:skill_id/end_ab_test
        def end_ab_test
          authorize_permission!("ai.skills.update")
          result = evolution_service.end_ab_test(skill_id: params[:skill_id])
          render_success(result)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/record_outcome
        def record_outcome
          authorize_permission!("ai.skills.update")
          evolution_service.record_outcome(
            skill_id: params[:skill_id],
            successful: params[:successful] == true || params[:successful] == "true"
          )
          render_success(recorded: true)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # ===================================================================
        # Optimization & Maintenance
        # ===================================================================

        # POST /api/v1/ai/skill_graph/optimize
        def run_optimization
          authorize_permission!("ai.knowledge_graph.manage")
          operation = params[:operation]&.to_sym || :full
          result = optimization_service.on_demand(operation: operation)
          render_success(result)
        rescue StandardError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skill_graph/maintenance/daily
        def maintenance_daily
          authorize_permission!("ai.analytics.manage")
          result = optimization_service.daily_maintenance
          render_success(result)
        end

        # POST /api/v1/ai/skill_graph/maintenance/weekly
        def maintenance_weekly
          authorize_permission!("ai.analytics.manage")
          result = optimization_service.weekly_maintenance
          render_success(result)
        end

        # POST /api/v1/ai/skill_graph/maintenance/monthly
        def maintenance_monthly
          authorize_permission!("ai.analytics.manage")
          result = optimization_service.monthly_maintenance
          render_success(result)
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

        def research_service
          @research_service ||= ::Ai::SkillGraph::ResearchService.new(current_account)
        end

        def lifecycle_service
          @lifecycle_service ||= ::Ai::SkillGraph::LifecycleService.new(current_account)
        end

        def conflict_detection_service
          @conflict_detection_service ||= ::Ai::SkillGraph::ConflictDetectionService.new(current_account)
        end

        def auto_repair_service
          @auto_repair_service ||= ::Ai::SkillGraph::AutoRepairService.new(current_account)
        end

        def evolution_service
          @evolution_service ||= ::Ai::SkillGraph::EvolutionService.new(current_account)
        end

        def health_score_service
          @health_score_service ||= ::Ai::SkillGraph::HealthScoreService.new(current_account)
        end

        def optimization_service
          @optimization_service ||= ::Ai::SkillGraph::OptimizationService.new(current_account)
        end

        def proposal_params
          params.permit(:name, :description, :category, :system_prompt, :agent_id,
                        commands: [:name, :description, :argument_hint],
                        tags: [])
                .to_h
                .merge(account: current_account, proposed_by_user: current_user)
        end

        def conflict_summary(conflict)
          {
            id: conflict.id,
            conflict_type: conflict.conflict_type,
            severity: conflict.severity,
            status: conflict.status,
            skill_a: { id: conflict.skill_a_id, name: conflict.skill_a.name },
            skill_b: conflict.skill_b ? { id: conflict.skill_b_id, name: conflict.skill_b.name } : nil,
            similarity_score: conflict.similarity_score,
            priority_score: conflict.priority_score,
            auto_resolvable: conflict.auto_resolvable,
            resolution_strategy: conflict.resolution_strategy,
            detected_at: conflict.detected_at,
            resolved_at: conflict.resolved_at
          }
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
