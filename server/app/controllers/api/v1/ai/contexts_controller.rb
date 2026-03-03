# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ContextsController < ApplicationController
        before_action :authenticate_request
        before_action :set_context, only: [ :show, :update, :destroy, :search, :archive, :unarchive, :export, :clone, :stats ]

        # GET /api/v1/ai/contexts
        def index
          authorize_action!("ai.context.read")
          return if performed?

          contexts = ::Ai::ContextPersistenceService.list_contexts(
            account: current_account,
            filters: context_filters,
            **pagination_params
          ).includes(:agent)

          render_success({
            contexts: contexts.map(&:context_summary),
            pagination: pagination_meta(contexts)
          })
        end

        # GET /api/v1/ai/contexts/:id
        def show
          authorize_action!("ai.context.read")
          return if performed?

          render_success({ context: @context.context_details })
        end

        # POST /api/v1/ai/contexts
        def create
          authorize_action!("ai.context.create")
          return if performed?

          context = ::Ai::ContextPersistenceService.create_context(
            account: current_account,
            attributes: context_params,
            created_by: current_user
          )

          render_success({ context: context.context_details }, status: :created)
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/contexts/:id
        def update
          authorize_action!("ai.context.update")
          return if performed?

          context = ::Ai::ContextPersistenceService.update_context(
            account: current_account,
            context_id: @context.id,
            attributes: context_params,
            accessor: current_user
          )

          render_success({ context: context.context_details })
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have write access to this context")
        end

        # DELETE /api/v1/ai/contexts/:id
        def destroy
          authorize_action!("ai.context.delete")
          return if performed?

          @context.destroy!

          render_success(message: "Context deleted")
        end

        # POST /api/v1/ai/contexts/:id/search
        def search
          authorize_action!("ai.context.read")
          return if performed?

          query = params[:query] || params[:q]
          search_type = params[:search_type] || "keyword"
          limit = (params[:limit] || 20).to_i

          results = perform_search(context: @context, query: query, search_type: search_type, limit: limit)

          render_success({
            results: results,
            query: query,
            search_type: search_type,
            total_results: results.size
          })
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have read access to this context")
        end

        # POST /api/v1/ai/contexts/search (collection - global search)
        def global_search
          authorize_action!("ai.context.read")
          return if performed?

          query = params[:query] || params[:q]
          search_type = params[:search_type] || "keyword"
          limit = (params[:limit] || 50).to_i

          contexts = ::Ai::PersistentContext.where(account: current_account).active.includes(:agent)
          all_results = []

          contexts.find_each do |context|
            ctx_results = perform_search(context: context, query: query, search_type: search_type, limit: limit)
            ctx_results.each { |r| r[:context] = context.context_summary }
            all_results.concat(ctx_results)
          end

          all_results.sort_by! { |r| -r[:score] }
          all_results = all_results.first(limit)

          render_success({
            results: all_results,
            query: query,
            search_type: search_type,
            total_results: all_results.size
          })
        end

        # POST /api/v1/ai/contexts/:id/archive
        def archive
          authorize_action!("ai.context.update")
          return if performed?

          ::Ai::ContextPersistenceService.archive_context(
            account: current_account,
            context_id: @context.id,
            accessor: current_user
          )

          render_success(message: "Context archived")
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have write access to this context")
        end

        # POST /api/v1/ai/contexts/:id/unarchive
        def unarchive
          authorize_action!("ai.context.update")
          return if performed?

          @context.unarchive!

          render_success({ context: @context.reload.context_summary })
        end

        # GET /api/v1/ai/contexts/:id/export
        def export
          authorize_action!("ai.context.export")
          return if performed?

          data = ::Ai::ContextPersistenceService.export_context(
            context: @context,
            accessor: current_user,
            format: params[:format]&.to_sym || :json
          )

          render_success({ export: JSON.parse(data) })
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have read access to this context")
        end

        # POST /api/v1/ai/contexts/:id/clone
        def clone
          authorize_action!("ai.context.create")
          return if performed?

          new_context = ::Ai::ContextPersistenceService.clone_context(
            account: current_account,
            context_id: @context.id,
            new_name: params[:name] || "#{@context.name} (Copy)",
            accessor: current_user
          )

          render_success({ context: new_context.context_details }, status: :created)
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have read access to this context")
        end

        # POST /api/v1/ai/contexts/import
        def import
          authorize_action!("ai.context.import")
          return if performed?

          context = ::Ai::ContextPersistenceService.import_context(
            account: current_account,
            data: params[:data],
            accessor: current_user,
            merge: params[:merge] == "true"
          )

          render_success({ context: context.context_details }, status: :created)
        rescue JSON::ParserError
          render_error("Invalid import data format", status: :unprocessable_content)
        end

        # GET /api/v1/ai/contexts/:id/stats
        def stats
          authorize_action!("ai.context.read")
          return if performed?

          entries = @context.context_entries
          render_success({
            stats: {
              total_entries: entries.count,
              entries_by_type: entries.group(:entry_type).count,
              data_size_bytes: entries.sum("COALESCE(octet_length(content::text), 0)"),
              avg_importance_score: entries.average(:importance_score)&.to_f&.round(2) || 0,
              access_count_total: entries.sum(:access_count),
              entries_with_embeddings: entries.where.not(embedding: nil).count,
              recent_accesses: entries.where("last_accessed_at >= ?", 7.days.ago).count
            }
          })
        end

        private

        def set_context
          @context = ::Ai::ContextPersistenceService.find_context(
            account: current_account,
            context_id: params[:id],
            accessor: current_user
          )
        rescue ::Ai::ContextPersistenceService::NotFoundError
          render_not_found("Context")
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have access to this context")
        end

        def context_params
          params.require(:context).permit(
            :name, :context_type, :scope, :description, :ai_agent_id,
            context_data: {},
            access_control: {},
            retention_policy: {}
          )
        end

        def context_filters
          {
            type: params[:type],
            scope: params[:scope],
            agent_id: params[:agent_id],
            include_archived: params[:include_archived] == "true"
          }.compact
        end

        def search_filters
          types = params[:entry_types] || params[:entry_type]
          types = Array(types).compact.presence if types.present?

          {
            type: types,
            min_importance: params[:min_importance]&.to_f
          }.compact
        end

        def perform_search(context:, query:, search_type:, limit:)
          results = []

          # Keyword search
          if %w[keyword hybrid].include?(search_type) && query.present?
            keyword_results = ::Ai::ContextPersistenceService.search(
              context: context,
              query: query,
              accessor: current_user,
              filters: search_filters,
              limit: limit
            )
            keyword_results.each do |entry|
              score = entry.importance_score || 0.5
              results << { entry: entry, score: score, highlights: extract_highlights(entry, query) }
            end
          end

          # Semantic search
          if %w[semantic hybrid].include?(search_type) && query.present?
            begin
              embedding_service = ::Ai::Memory::EmbeddingService.new(account: current_account)
              query_embedding = embedding_service.generate(query)
              if query_embedding
                semantic_results = ::Ai::ContextPersistenceService.semantic_search(
                  context: context,
                  query_embedding: query_embedding,
                  accessor: current_user,
                  limit: limit
                )
                semantic_results.each do |entry|
                  score = (1.0 - (entry.neighbor_distance || 0.0)).round(4)
                  existing = results.find { |r| r[:entry].id == entry.id }
                  if existing
                    existing[:score] = [existing[:score], score].max
                  else
                    results << { entry: entry, score: score, highlights: [] }
                  end
                end
              end
            rescue StandardError => e
              Rails.logger.warn("Semantic search failed: #{e.message}")
            end
          end

          # Sort by score and format
          results.sort_by! { |r| -r[:score] }
          results.first(limit).map do |r|
            {
              entry: r[:entry].entry_summary,
              score: r[:score].round(4),
              highlights: r[:highlights] || []
            }
          end
        end

        def extract_highlights(entry, query)
          return [] unless query.present? && entry.content_text.present?

          text = entry.content_text
          highlights = []
          query_terms = query.downcase.split(/\s+/)

          query_terms.each do |term|
            next if term.length < 2

            idx = text.downcase.index(term)
            next unless idx

            start_pos = [idx - 50, 0].max
            end_pos = [idx + term.length + 50, text.length].min
            snippet = text[start_pos...end_pos]
            snippet = "...#{snippet}" if start_pos > 0
            snippet = "#{snippet}..." if end_pos < text.length

            highlighted = snippet.gsub(/(#{Regexp.escape(term)})/i, '<mark>\1</mark>')
            highlights << highlighted
          end

          highlights.uniq.first(3)
        end

        def authorize_action!(permission)
          return if current_user.has_permission?(permission)

          render_forbidden("You don't have permission to perform this action")
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
