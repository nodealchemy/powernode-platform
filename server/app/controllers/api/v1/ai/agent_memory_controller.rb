# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AgentMemoryController < ApplicationController
        before_action :authenticate_request
        before_action :set_agent

        # GET /api/v1/ai/agents/:agent_id/memory
        def index
          authorize_action!("ai.memory.read")
          return if performed?

          context = ::Ai::ContextPersistenceService.get_agent_memory(
            account: current_account,
            agent: @agent,
            create_if_missing: false
          )

          if context.nil?
            return render_success({
              memory: nil,
              entries: [],
              message: "No memory context exists for this agent"
            })
          end

          entries = context.context_entries
            .active
            .order(importance_score: :desc, updated_at: :desc)
            .page(pagination_params[:page])
            .per(pagination_params[:per_page])

          render_success(
            memory: context.context_summary,
            entries: entries.map(&:entry_summary),
            pagination: pagination_meta(entries)
          )
        end

        # GET /api/v1/ai/agents/:agent_id/memory/:key
        def show
          authorize_action!("ai.memory.read")
          return if performed?

          value = ::Ai::ContextPersistenceService.recall_memory(
            agent: @agent,
            key: params[:key]
          )

          if value.nil?
            render_not_found("Memory entry")
          else
            render_success(key: params[:key], value: value)
          end
        end

        # POST /api/v1/ai/agents/:agent_id/memory
        def create
          authorize_action!("ai.memory.write")
          return if performed?

          entry = ::Ai::ContextPersistenceService.store_memory(
            agent: @agent,
            key: memory_params[:key],
            value: memory_params[:value],
            type: memory_params[:type] || "memory",
            metadata: memory_params[:metadata] || {}
          )

          render_success(entry: entry.entry_summary, status: :created)
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/agents/:agent_id/memory/:key
        def update
          authorize_action!("ai.memory.write")
          return if performed?

          entry = ::Ai::ContextPersistenceService.store_memory(
            agent: @agent,
            key: params[:key],
            value: memory_params[:value],
            type: memory_params[:type],
            metadata: memory_params[:metadata] || {}
          )

          render_success(entry: entry.entry_summary)
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/agents/:agent_id/memory/:key
        def destroy
          authorize_action!("ai.memory.write")
          return if performed?

          context = ::Ai::ContextPersistenceService.get_agent_memory(
            account: current_account,
            agent: @agent,
            create_if_missing: false
          )

          if context.nil?
            return render_not_found("Memory context")
          end

          ::Ai::ContextPersistenceService.delete_entry(
            context: context,
            key: params[:key],
            accessor: @agent
          )

          render_success(message: "Memory entry deleted")
        rescue ::Ai::ContextPersistenceService::NotFoundError
          render_not_found("Memory entry")
        end

        # POST /api/v1/ai/agents/:agent_id/memory/search
        def search
          authorize_action!("ai.memory.read")
          return if performed?

          memories = ::Ai::ContextPersistenceService.get_relevant_memories(
            agent: @agent,
            query: params[:q],
            limit: (params[:limit] || 10).to_i
          )

          render_success(memories: memories.map(&:entry_summary))
        end

        # POST /api/v1/ai/agents/:agent_id/memory/clear
        def clear
          authorize_action!("ai.memory.manage")
          return if performed?

          context = ::Ai::ContextPersistenceService.get_agent_memory(
            account: current_account,
            agent: @agent,
            create_if_missing: false
          )

          if context.nil?
            return render_success({ message: "No memory to clear", cleared: 0 })
          end

          count = context.context_entries.count
          context.context_entries.destroy_all

          render_success({ message: "Memory cleared", cleared: count })
        end

        # GET /api/v1/ai/agents/:agent_id/memory/stats
        def stats
          authorize_action!("ai.memory.read")
          return if performed?

          context = ::Ai::ContextPersistenceService.get_agent_memory(
            account: current_account,
            agent: @agent,
            create_if_missing: false
          )

          if context.nil?
            return render_success(
              stats: {
                entry_count: 0,
                has_memory: false
              }
            )
          end

          health = ::Ai::Memory::MaintenanceService.new(account: current_account).context_health(context: context)

          render_success(
            stats: health.merge(
              has_memory: true,
              context_id: context.id
            )
          )
        end

        # POST /api/v1/ai/agents/:agent_id/memory/sync
        def sync
          authorize_action!("ai.memory.manage")
          return if performed?

          source_context = ::Ai::PersistentContext.find_by(
            id: params[:source_context_id],
            account: current_account
          )

          unless source_context
            return render_not_found("Source context")
          end

          target_context = ::Ai::ContextPersistenceService.get_agent_memory(
            account: current_account,
            agent: @agent
          )

          result = ::Ai::Memory::MaintenanceService.new(account: current_account).sync_context(
            from_context: source_context,
            to_context: target_context,
            entry_types: params[:entry_types],
            min_importance: params[:min_importance]&.to_f
          )

          render_success({
            synced: result[:synced],
            message: "Synced #{result[:synced]} entries from source context"
          })
        end

        private

        def set_agent
          @agent = ::Ai::Agent.find_by(id: params[:agent_id], account: current_account)

          render_not_found("Agent") unless @agent
        end

        def memory_params
          params.require(:memory).permit(:key, :type, value: {}, metadata: {})
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("You don't have permission to perform this action")
          end
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
