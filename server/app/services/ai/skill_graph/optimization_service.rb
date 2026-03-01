# frozen_string_literal: true

module Ai
  module SkillGraph
    class OptimizationService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Run daily maintenance: conflict scan, auto-resolve, decay, stats refresh
      def daily_maintenance
        return maintenance_disabled_result unless Shared::FeatureFlagService.enabled?(:skill_optimization, account)

        results = {
          conflicts_found: 0,
          auto_resolved: 0,
          skills_decayed: 0,
          stats: nil,
          ran_at: Time.current.iso8601
        }

        # 1. Scan for conflicts
        results[:conflicts_found] = conflict_detection_service.scan_all
        Rails.logger.info "[SkillGraph::Optimization] Daily: found #{results[:conflicts_found]} conflicts"

        # 2. Auto-resolve if enabled
        if Shared::FeatureFlagService.enabled?(:skill_conflict_auto_resolve, account)
          results[:auto_resolved] = auto_repair_service.auto_resolve_all
          Rails.logger.info "[SkillGraph::Optimization] Daily: auto-resolved #{results[:auto_resolved]} conflicts"
        end

        # 3. Decay stale skills
        results[:skills_decayed] = evolution_service.decay_stale_skills
        Rails.logger.info "[SkillGraph::Optimization] Daily: decayed #{results[:skills_decayed]} stale skills"

        # 4. Refresh KG stats (warm cache)
        results[:stats] = graph_service.statistics
        Rails.logger.info "[SkillGraph::Optimization] Daily: stats refreshed"

        results
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Optimization] daily_maintenance failed: #{e.message}"
        results.merge(error: e.message)
      end

      # Run weekly maintenance: prompt refinements, gap detection, effectiveness recalc, health snapshot
      def weekly_maintenance
        return maintenance_disabled_result unless Shared::FeatureFlagService.enabled?(:skill_optimization, account)

        results = {
          refinements_proposed: 0,
          gaps_detected: {},
          effectiveness_updated: 0,
          health_score: nil,
          ran_at: Time.current.iso8601
        }

        # 1. Propose prompt refinements
        refinement_ids = self_learning_service.propose_prompt_refinements
        results[:refinements_proposed] = refinement_ids.size
        Rails.logger.info "[SkillGraph::Optimization] Weekly: proposed #{results[:refinements_proposed]} refinements"

        # 2. Detect capability gaps
        results[:gaps_detected] = self_learning_service.detect_capability_gaps
        Rails.logger.info "[SkillGraph::Optimization] Weekly: gap detection complete"

        # 3. Recalculate all effectiveness scores
        results[:effectiveness_updated] = self_learning_service.recalculate_all_effectiveness
        Rails.logger.info "[SkillGraph::Optimization] Weekly: recalculated #{results[:effectiveness_updated]} effectiveness scores"

        # 4. Health score snapshot
        results[:health_score] = health_score_service.calculate
        Rails.logger.info "[SkillGraph::Optimization] Weekly: health score = #{results[:health_score][:score]}"

        results
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Optimization] weekly_maintenance failed: #{e.message}"
        results.merge(error: e.message)
      end

      # Run monthly maintenance: re-embed all skills, comprehensive report, archive old conflicts
      def monthly_maintenance
        return maintenance_disabled_result unless Shared::FeatureFlagService.enabled?(:skill_optimization, account)

        results = {
          skills_reembedded: {},
          health_report: nil,
          conflicts_archived: 0,
          ran_at: Time.current.iso8601
        }

        # 1. Re-embed all skills
        results[:skills_reembedded] = bridge_service.sync_all_skills
        Rails.logger.info "[SkillGraph::Optimization] Monthly: re-embedded #{results[:skills_reembedded][:synced]} skills"

        # 2. Comprehensive health report
        results[:health_report] = health_score_service.comprehensive_report
        Rails.logger.info "[SkillGraph::Optimization] Monthly: comprehensive report generated"

        # 3. Archive old resolved conflicts (> 90 days)
        archived = Ai::SkillConflict.where(account: account)
          .where(status: %w[resolved auto_resolved dismissed])
          .where("resolved_at < ?", 90.days.ago)

        results[:conflicts_archived] = archived.count
        archived.delete_all
        Rails.logger.info "[SkillGraph::Optimization] Monthly: archived #{results[:conflicts_archived]} old conflicts"

        results
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Optimization] monthly_maintenance failed: #{e.message}"
        results.merge(error: e.message)
      end

      # Run specific or combined operations on demand
      def on_demand(operation:)
        return maintenance_disabled_result unless Shared::FeatureFlagService.enabled?(:skill_optimization, account)

        case operation.to_sym
        when :full
          daily = daily_maintenance
          weekly = weekly_maintenance
          { daily: daily, weekly: weekly }
        when :scan_conflicts
          { conflicts_found: conflict_detection_service.scan_all }
        when :auto_resolve
          { auto_resolved: auto_repair_service.auto_resolve_all }
        when :decay
          { skills_decayed: evolution_service.decay_stale_skills }
        when :refinements
          { refinements_proposed: self_learning_service.propose_prompt_refinements.size }
        when :gaps
          { gaps: self_learning_service.detect_capability_gaps }
        when :effectiveness
          { effectiveness_updated: self_learning_service.recalculate_all_effectiveness }
        when :health
          { health: health_score_service.calculate }
        when :reembed
          { skills_reembedded: bridge_service.sync_all_skills }
        else
          Rails.logger.warn "[SkillGraph::Optimization] Unknown operation: #{operation}"
          { error: "Unknown operation: #{operation}" }
        end
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Optimization] on_demand(#{operation}) failed: #{e.message}"
        { error: e.message }
      end

      private

      def maintenance_disabled_result
        { skipped: true, reason: "skill_optimization feature flag disabled" }
      end

      def conflict_detection_service
        @conflict_detection_service ||= Ai::SkillGraph::ConflictDetectionService.new(account)
      end

      def auto_repair_service
        @auto_repair_service ||= Ai::SkillGraph::AutoRepairService.new(account)
      end

      def evolution_service
        @evolution_service ||= Ai::SkillGraph::EvolutionService.new(account)
      end

      def self_learning_service
        @self_learning_service ||= Ai::SkillGraph::SelfLearningService.new(account)
      end

      def health_score_service
        @health_score_service ||= Ai::SkillGraph::HealthScoreService.new(account)
      end

      def bridge_service
        @bridge_service ||= Ai::SkillGraph::BridgeService.new(account)
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end
    end
  end
end
