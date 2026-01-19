# frozen_string_literal: true

module AiContext
  class MemorySyncJob < BaseJob
    sidekiq_options queue: 'ai',
                    retry: 3,
                    dead: true

    # Sync memory between contexts or agents
    def execute(params = {})
      action = params[:action] || "sync"

      case action
      when "sync"
        sync_contexts(params)
      when "consolidate"
        consolidate_memories(params)
      when "decay"
        decay_importance_scores(params)
      when "boost"
        boost_frequent_entries(params)
      else
        log_error("Unknown memory sync action", action: action)
        { success: false, error: "Unknown action: #{action}" }
      end
    end

    private

    def sync_contexts(params)
      from_context_id = params[:from_context_id]
      to_context_id = params[:to_context_id]
      entry_types = params[:entry_types]
      min_importance = params[:min_importance]

      unless from_context_id && to_context_id
        return { success: false, error: "from_context_id and to_context_id are required" }
      end

      log_info("Syncing contexts",
               from: from_context_id,
               to: to_context_id,
               types: entry_types)

      response = api_client.post("/api/v1/internal/ai_context/sync", {
        from_context_id: from_context_id,
        to_context_id: to_context_id,
        entry_types: entry_types,
        min_importance: min_importance
      })

      if response[:success]
        synced = response[:data][:synced] || 0
        log_info("Context sync completed", synced: synced)
        increment_counter("memory_sync_success")

        { success: true, synced: synced }
      else
        log_error("Context sync failed", error: response[:error])
        increment_counter("memory_sync_failure")

        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      log_error("Context sync error", exception: e)
      { success: false, error: e.message }
    end

    def consolidate_memories(params)
      context_id = params[:context_id]
      similarity_threshold = params[:similarity_threshold] || 0.9

      unless context_id
        return { success: false, error: "context_id is required" }
      end

      log_info("Consolidating memories", context_id: context_id, threshold: similarity_threshold)

      response = api_client.post("/api/v1/internal/ai_context/consolidate", {
        context_id: context_id,
        similarity_threshold: similarity_threshold
      })

      if response[:success]
        consolidated = response[:data][:consolidated] || 0
        log_info("Memory consolidation completed", consolidated: consolidated)

        { success: true, consolidated: consolidated }
      else
        log_error("Memory consolidation failed", error: response[:error])
        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      log_error("Memory consolidation error", exception: e)
      { success: false, error: e.message }
    end

    def decay_importance_scores(params)
      context_id = params[:context_id]
      decay_rate = params[:decay_rate] || 0.01

      log_info("Decaying importance scores", context_id: context_id, rate: decay_rate)

      request_params = { decay_rate: decay_rate }
      request_params[:context_id] = context_id if context_id

      response = api_client.post("/api/v1/internal/ai_context/decay", request_params)

      if response[:success]
        updated = response[:data][:updated] || 0
        log_info("Importance decay completed", updated: updated)

        { success: true, updated: updated }
      else
        log_error("Importance decay failed", error: response[:error])
        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      log_error("Importance decay error", exception: e)
      { success: false, error: e.message }
    end

    def boost_frequent_entries(params)
      context_id = params[:context_id]
      access_threshold = params[:access_threshold] || 10
      boost_amount = params[:boost_amount] || 0.1

      log_info("Boosting frequently accessed entries",
               context_id: context_id,
               threshold: access_threshold,
               boost: boost_amount)

      request_params = {
        access_threshold: access_threshold,
        boost_amount: boost_amount
      }
      request_params[:context_id] = context_id if context_id

      response = api_client.post("/api/v1/internal/ai_context/boost", request_params)

      if response[:success]
        updated = response[:data][:updated] || 0
        log_info("Frequency boost completed", updated: updated)

        { success: true, updated: updated }
      else
        log_error("Frequency boost failed", error: response[:error])
        { success: false, error: response[:error] }
      end
    rescue StandardError => e
      log_error("Frequency boost error", exception: e)
      { success: false, error: e.message }
    end
  end
end
