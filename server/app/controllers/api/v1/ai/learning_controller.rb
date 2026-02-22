# frozen_string_literal: true

module Api
  module V1
    module Ai
      class LearningController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/learning/recommendations
        def recommendations
          recs = ::Ai::ImprovementRecommendation.where(account: current_account)
                                                 .recent(params[:limit]&.to_i || 50)

          recs = recs.where(status: params[:status]) if params[:status].present?
          recs = recs.by_type(params[:type]) if params[:type].present?

          render_success(
            recommendations: recs.map { |r| recommendation_json(r) }
          )
        end

        # POST /api/v1/ai/learning/recommendations/:id/apply
        def apply_recommendation
          recommender = ::Ai::Learning::ImprovementRecommender.new(account: current_account)
          recommendation = recommender.apply_recommendation!(params[:id], user: current_user)

          if recommendation
            render_success(recommendation: recommendation_json(recommendation))
          else
            render_error("Recommendation not found or cannot be applied", status: :not_found)
          end
        end

        # POST /api/v1/ai/learning/recommendations/:id/dismiss
        def dismiss_recommendation
          recommendation = ::Ai::ImprovementRecommendation.find_by(
            id: params[:id], account: current_account
          )

          if recommendation
            recommendation.dismiss!
            render_success(recommendation: recommendation_json(recommendation))
          else
            render_error("Recommendation not found", status: :not_found)
          end
        end

        # GET /api/v1/ai/learning/agent_trends
        def agent_trends
          evaluation_service = ::Ai::Learning::EvaluationService.new(account: current_account)
          agents = current_account.ai_agents.where(status: "active")

          trends = agents.filter_map do |agent|
            trend_data = evaluation_service.agent_score_trends(agent.id)
            next if trend_data.blank?

            trend_data.merge(agent_id: agent.id, agent_name: agent.name)
          end

          render_success(trends: trends)
        end

        # GET /api/v1/ai/learning/cache_metrics
        def cache_metrics
          metrics = ::Ai::Learning::PromptCacheService.metrics

          render_success(metrics: metrics)
        end

        # GET /api/v1/ai/learning/compound_metrics
        def compound_metrics
          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)
          metrics = service.compound_metrics

          render_success(metrics: metrics)
        end

        # GET /api/v1/ai/learning/learnings
        def learnings
          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)
          results = service.list_learnings(
            status: params[:status] || "active",
            category: params[:category],
            scope: params[:scope],
            min_importance: params[:min_importance]&.to_f,
            team_id: params[:team_id],
            query: params[:query],
            limit: params[:limit]&.to_i || 50
          )

          render_success(
            learnings: results.map { |l| l.respond_to?(:learning_summary) ? l.learning_summary : l }
          )
        end

        # POST /api/v1/ai/learning/reinforce/:id
        def reinforce
          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)
          learning = service.reinforce_learning(params[:id])

          if learning
            render_success(learning: learning.learning_summary)
          else
            render_error("Learning not found", status: :not_found)
          end
        end

        # POST /api/v1/ai/learning/promote
        def promote
          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)
          count = service.promote_cross_team

          render_success(promoted_count: count)
        end

        # GET /api/v1/ai/learning/benchmarks
        def benchmarks
          benchmarks = ::Ai::PerformanceBenchmark.where(account: current_account)
          benchmarks = benchmarks.where(status: params[:status]) if params[:status].present?
          benchmarks = benchmarks.for_agent(params[:agent_id]) if params[:agent_id].present?
          benchmarks = benchmarks.order(created_at: :desc).limit(params[:limit]&.to_i || 50)

          render_success(
            benchmarks: benchmarks.map { |b| benchmark_json(b) }
          )
        end

        # POST /api/v1/ai/learning/benchmarks
        def create_benchmark
          benchmark = ::Ai::PerformanceBenchmark.new(
            account: current_account,
            name: params[:name],
            target_agent_id: params[:agent_id],
            target_workflow_id: params[:workflow_id],
            thresholds: params[:thresholds] || {},
            status: "active"
          )

          if benchmark.save
            render_success(benchmark: benchmark_json(benchmark))
          else
            render_error(benchmark.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/learning/benchmarks/:id/run
        def run_benchmark
          benchmark = ::Ai::PerformanceBenchmark.find_by(id: params[:id], account: current_account)
          return render_error("Benchmark not found", status: :not_found) unless benchmark

          evaluation_service = ::Ai::Learning::EvaluationService.new(account: current_account)
          agent_id = benchmark.target_agent_id
          return render_error("Benchmark has no target agent", status: :unprocessable_content) unless agent_id

          trend_data = evaluation_service.agent_score_trends(agent_id)
          benchmark.record_results!(trend_data || {})

          render_success(
            benchmark: benchmark_json(benchmark),
            results: trend_data
          )
        end

        # GET /api/v1/ai/learning/evaluation_results
        def evaluation_results
          results = ::Ai::EvaluationResult.joins(:execution)
                                           .where(ai_agent_executions: { account_id: current_account.id })

          results = results.for_agent(params[:agent_id]) if params[:agent_id].present?
          results = results.in_time_range(params[:from]&.to_datetime, params[:to]&.to_datetime) if params[:from].present?
          results = results.order(created_at: :desc).limit(params[:limit]&.to_i || 50)

          render_success(
            results: results.map { |r| evaluation_result_json(r) }
          )
        end

        # POST /api/v1/ai/learning/memory_maintenance (internal, called by worker)
        def memory_maintenance
          maintenance = ::Ai::Memory::MaintenanceService.new(account: current_account)
          maintenance_result = maintenance.run_full_maintenance

          rot_service = ::Ai::Context::RotDetectionService.new(account: current_account)
          rot_result = rot_service.auto_archive!

          render_success(
            maintenance: maintenance_result,
            rot_detection: rot_result
          )
        end

        # POST /api/v1/ai/learning/knowledge_doc_sync (internal, called by worker)
        def knowledge_doc_sync
          service = ::Ai::KnowledgeDocSyncService.new(account: current_account)
          result = service.sync_all!

          if result[:success]
            render_success(data: result)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/learning/knowledge_graph_maintenance (internal, called by worker)
        def knowledge_graph_maintenance
          all_nodes = ::Ai::KnowledgeGraphNode.active.where(account: current_account)
          # Skip nodes recently processed by event-driven jobs
          nodes = all_nodes.where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)
          skipped = all_nodes.where("last_event_processed_at >= ?", 24.hours.ago).count

          decayed = 0
          recalculated = 0

          nodes.find_each do |node|
            node.decay_confidence!
            decayed += 1

            node.recalculate_quality_score!
            recalculated += 1
          rescue StandardError => e
            Rails.logger.warn("[KnowledgeGraphMaintenance] Failed for node #{node.id}: #{e.message}")
          end

          Rails.logger.info("[KnowledgeGraphMaintenance] decayed=#{decayed} recalculated=#{recalculated} skipped_by_event=#{skipped}")

          render_success(
            decayed: decayed,
            recalculated: recalculated,
            skipped_by_event: skipped
          )
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/learning/promote_learning (event-driven, called by worker)
        def promote_learning
          learning = ::Ai::CompoundLearning.find_by(id: params[:learning_id], account: current_account)
          return render_error("Learning not found", status: :not_found) unless learning

          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)

          # Check if already promoted globally
          existing_global = ::Ai::CompoundLearning.active
            .for_account(current_account.id)
            .global_scope
            .where("content ILIKE ?", "%#{learning.content.truncate(100)}%")

          if existing_global.exists?
            render_success(promoted: false, reason: "already_global")
          else
            promoted = ::Ai::CompoundLearning.create!(
              account: current_account,
              category: learning.category,
              content: learning.content,
              title: learning.title,
              importance_score: learning.importance_score,
              confidence_score: learning.confidence_score,
              scope: "global",
              extraction_method: learning.extraction_method,
              tags: learning.tags,
              applicable_domains: learning.applicable_domains,
              embedding: learning.embedding,
              promoted_at: Time.current,
              metadata: { promoted_from_team: learning.ai_agent_team_id, original_id: learning.id }
            )
            learning.update_column(:last_event_processed_at, Time.current) if learning.respond_to?(:last_event_processed_at)
            render_success(promoted: true, learning_id: promoted.id)
          end
        rescue StandardError => e
          Rails.logger.error("[PromoteLearning] Failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/learning/dedup_check (event-driven, called by worker)
        def dedup_check
          learning = ::Ai::CompoundLearning.find_by(id: params[:learning_id], account: current_account)
          return render_error("Learning not found", status: :not_found) unless learning
          return render_success(dedup: false, reason: "no_embedding") unless learning.embedding.present?

          duplicates = ::Ai::CompoundLearning.find_similar(
            learning.embedding,
            account_id: current_account.id,
            threshold: 0.92
          ).where.not(id: learning.id)

          if duplicates.any?
            existing = duplicates.first
            existing.boost_importance!(0.03)
            learning.deprecate!
            render_success(dedup: true, merged_into: existing.id)
          else
            learning.update_column(:last_event_processed_at, Time.current) if learning.respond_to?(:last_event_processed_at)
            render_success(dedup: false, reason: "unique")
          end
        rescue StandardError => e
          Rails.logger.error("[DedupCheck] Failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/learning/update_graph_node (event-driven, called by worker)
        def update_graph_node
          node = ::Ai::KnowledgeGraphNode.find_by(id: params[:node_id], account: current_account)
          return render_error("Node not found", status: :not_found) unless node

          node.decay_confidence!
          node.recalculate_quality_score!
          node.update_column(:last_event_processed_at, Time.current) if node.respond_to?(:last_event_processed_at)

          render_success(
            node_id: node.id,
            confidence: node.confidence,
            quality_score: node.quality_score
          )
        rescue StandardError => e
          Rails.logger.error("[UpdateGraphNode] Failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/learning/compound_maintenance (internal, called by worker)
        def compound_maintenance
          service = ::Ai::Learning::CompoundLearningService.new(account: current_account)

          maintenance_result = service.decay_and_consolidate
          promotion_count = service.promote_cross_team

          render_success(
            maintenance: maintenance_result,
            promoted: promotion_count
          )
        end

        private

        def validate_permissions
          # Worker bypass for internal maintenance endpoints (same pattern as TieredMemoryController)
          if current_worker
            return if %w[compound_maintenance memory_maintenance knowledge_doc_sync knowledge_graph_maintenance
                         promote_learning dedup_check update_graph_node].include?(action_name)
          end

          case action_name
          when "recommendations", "agent_trends", "cache_metrics", "evaluation_results", "benchmarks"
            require_permission("ai.analytics.read")
          when "compound_metrics", "learnings"
            require_permission("ai.analytics.read")
          when "apply_recommendation", "dismiss_recommendation", "create_benchmark", "run_benchmark"
            require_permission("ai.analytics.manage")
          when "reinforce", "promote", "compound_maintenance", "memory_maintenance", "knowledge_doc_sync", "knowledge_graph_maintenance"
            require_permission("ai.analytics.manage")
          when "promote_learning", "dedup_check", "update_graph_node"
            require_permission("ai.analytics.manage")
          end
        end

        def recommendation_json(rec)
          {
            id: rec.id,
            recommendation_type: rec.recommendation_type,
            target_type: rec.target_type,
            target_id: rec.target_id,
            current_config: rec.current_config,
            recommended_config: rec.recommended_config,
            evidence: rec.evidence,
            confidence_score: rec.confidence_score,
            status: rec.status,
            created_at: rec.created_at&.iso8601
          }
        end

        def benchmark_json(benchmark)
          {
            id: benchmark.id,
            name: benchmark.name,
            status: benchmark.status,
            target_agent_id: benchmark.target_agent_id,
            target_workflow_id: benchmark.target_workflow_id,
            baseline_metrics: benchmark.baseline_metrics,
            latest_results: benchmark.latest_results,
            latest_score: benchmark.latest_score,
            trend: benchmark.trend,
            thresholds: benchmark.thresholds,
            last_run_at: benchmark.last_run_at&.iso8601,
            created_at: benchmark.created_at&.iso8601
          }
        end

        def evaluation_result_json(result)
          {
            id: result.id,
            execution_id: result.ai_agent_execution_id,
            evaluator_model: result.evaluator_model,
            scores: result.scores,
            feedback: result.feedback,
            correctness: result.correctness_score,
            completeness: result.completeness_score,
            helpfulness: result.helpfulness_score,
            safety: result.safety_score,
            average: result.average_score,
            created_at: result.created_at&.iso8601
          }
        end
      end
    end
  end
end
