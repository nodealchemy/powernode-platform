# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TieredMemoryController < ApplicationController
        before_action :validate_permissions
        before_action :set_agent

        # GET /api/v1/ai/agents/:agent_id/tiered_memory/stats
        def stats
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)

          render_success(data: router.stats)
        end

        # GET /api/v1/ai/agents/:agent_id/tiered_memory
        def index
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)

          if params[:key].present?
            result = router.read(
              key: params[:key],
              session_id: params[:session_id],
              tier: params[:tier]
            )
            render_success(data: result)
          else
            # Return memories from the specified tier (or short_term by default)
            tier = params[:tier] || "short_term"
            entries = fetch_entries_for_tier(tier)
            render_success(data: { tier: tier, entries: entries })
          end
        end

        # POST /api/v1/ai/agents/:agent_id/tiered_memory
        def create
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)

          result = router.write(
            key: memory_params[:key],
            value: memory_params[:value],
            tier: memory_params[:tier] || "short_term",
            session_id: memory_params[:session_id],
            type: memory_params[:type],
            ttl: memory_params[:ttl]&.to_i,
            tags: memory_params[:tags]
          )

          if result[:success]
            render_success(data: result, status: :created)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/agents/:agent_id/tiered_memory/:key
        def destroy
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)

          result = router.delete(
            key: params[:key],
            tier: params[:tier] || "short_term",
            session_id: params[:session_id]
          )

          if result[:success]
            render_success(message: "Memory entry deleted")
          else
            render_error(result[:error] || "Failed to delete memory entry", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/agents/:agent_id/tiered_memory/consolidate
        def consolidate
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)

          unless params[:session_id].present?
            return render_error("session_id is required", status: :bad_request)
          end

          result = router.consolidate!(session_id: params[:session_id])

          render_success(data: result)
        end

        # POST /api/v1/ai/memory/consolidate
        def consolidate_all
          maintenance = ::Ai::Memory::MaintenanceService.new(account: current_account)
          result = maintenance.run_consolidation_pipeline

          render_success(data: result)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/memory/decay
        def decay_all
          maintenance = ::Ai::Memory::MaintenanceService.new(account: current_account)
          result = maintenance.run_decay_pipeline

          render_success(data: result)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/memory/shared_maintenance
        def shared_maintenance
          shared = ::Ai::Memory::SharedKnowledgeService.new(account: current_account)
          result = shared.import_from_learnings(min_importance: 0.7)
          quality_result = shared.recalculate_all_quality
          stats = shared.stats

          render_success(data: { import_result: result, quality_recalc: quality_result, stats: stats })
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/memory/consolidate_entry (event-driven, called by worker)
        def consolidate_entry
          entry = ::Ai::AgentShortTermMemory.find_by(id: params[:entry_id])
          return render_error("Entry not found", status: :not_found) unless entry
          return render_success(consolidated: false, reason: "expired") if entry.expired?

          # Promote to long-term via embedding-based consolidation
          agent = entry.agent
          router = ::Ai::Memory::RouterService.new(account: current_account, agent: agent)
          result = router.consolidate!(session_id: entry.session_id)

          entry.update_column(:last_event_processed_at, Time.current) if entry.respond_to?(:last_event_processed_at)

          render_success(data: result)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/memory/shared_knowledge
        def shared_knowledge
          scope = ::Ai::SharedKnowledge
            .where(account_id: current_account.id)
            .accessible_by("account")
            .recent

          scope = scope.by_content_type(params[:content_type]) if params[:content_type].present?
          scope = scope.with_tag(params[:tag]) if params[:tag].present?
          scope = scope.high_quality if params[:high_quality] == "true"

          entries = scope.limit(params[:limit]&.to_i || 50)

          render_success(data: entries.map { |e| serialize_shared_knowledge(e) })
        end

        private

        def set_agent
          # These actions don't require an agent
          return if %w[shared_knowledge consolidate_all decay_all shared_maintenance consolidate_entry].include?(action_name)

          @agent = current_account.ai_agents.find(params[:agent_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Agent")
        end

        def validate_permissions
          return if current_worker || current_service

          case action_name
          when "index", "stats", "shared_knowledge"
            require_permission("ai.memory.read")
          when "create", "consolidate", "consolidate_all", "decay_all", "shared_maintenance", "consolidate_entry"
            require_permission("ai.memory.write")
          when "destroy"
            require_permission("ai.memory.write")
          end
        end

        def memory_params
          params.permit(:key, :tier, :session_id, :type, :ttl, value: {}, tags: [])
        end

        def fetch_entries_for_tier(tier)
          case tier
          when "short_term"
            ::Ai::AgentShortTermMemory
              .for_agent(@agent.id)
              .active
              .recent
              .limit(params[:limit]&.to_i || 50)
              .map { |m| serialize_short_term(m) }
          when "working"
            # Working memory is Redis-backed, return count only
            router = ::Ai::Memory::RouterService.new(account: current_account, agent: @agent)
            stats = router.stats
            [{ tier: "working", summary: stats[:working] }]
          when "long_term"
            ::Ai::CompoundLearning
              .where(account_id: current_account.id, source_agent_id: @agent.id)
              .active
              .order(created_at: :desc)
              .limit(params[:limit]&.to_i || 50)
              .map { |cl| serialize_long_term(cl) }
          when "shared"
            ::Ai::SharedKnowledge
              .where(account_id: current_account.id)
              .accessible_by("team")
              .recent
              .limit(params[:limit]&.to_i || 50)
              .map { |sk| serialize_shared_knowledge(sk) }
          else
            []
          end
        end

        def serialize_short_term(memory)
          {
            id: memory.id,
            key: memory.memory_key,
            value: memory.memory_value,
            type: memory.memory_type,
            session_id: memory.session_id,
            access_count: memory.access_count,
            expires_at: memory.expires_at,
            expired: memory.expired?,
            created_at: memory.created_at
          }
        end

        def serialize_long_term(learning)
          {
            id: learning.id,
            key: learning.metadata&.dig("memory_key"),
            content: learning.content,
            category: learning.category,
            importance_score: learning.importance_score,
            confidence_score: learning.confidence_score,
            created_at: learning.created_at
          }
        end

        def serialize_shared_knowledge(knowledge)
          {
            id: knowledge.id,
            title: knowledge.title,
            content: knowledge.content,
            content_type: knowledge.content_type,
            access_level: knowledge.access_level,
            source_type: knowledge.source_type,
            tags: knowledge.tags,
            quality_score: knowledge.quality_score,
            usage_count: knowledge.usage_count,
            last_used_at: knowledge.last_used_at,
            created_at: knowledge.created_at
          }
        end
      end
    end
  end
end
