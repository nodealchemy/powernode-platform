# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ContextEntriesController < ApplicationController
        class UnauthorizedActionError < StandardError; end

        before_action :authenticate_request
        before_action :set_context
        before_action :set_entry, only: [:show, :update, :destroy, :archive, :unarchive, :boost, :history]

        rescue_from UnauthorizedActionError do |_e|
          render_forbidden("You don't have permission to perform this action")
        end

        # GET /api/v1/ai/contexts/:context_id/entries
        def index
          authorize_action!("ai.context.read")

          entries = ::Ai::ContextPersistenceService.list_entries(
            context: @context,
            filters: entry_filters,
            accessor: current_user,
            **pagination_params
          )

          render_success(
            entries: entries.map(&:entry_summary),
            pagination: pagination_meta(entries)
          )
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have read access to this context")
        end

        # GET /api/v1/ai/contexts/:context_id/entries/:id
        def show
          authorize_action!("ai.context.read")

          render_success(entry: @entry.entry_details)
        end

        # POST /api/v1/ai/contexts/:context_id/entries
        def create
          authorize_action!("ai.context.create")

          entry = ::Ai::ContextPersistenceService.add_entry(
            context: @context,
            attributes: entry_params,
            accessor: current_user
          )

          render_success(entry: entry.entry_details, status: :created)
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have write access to this context")
        end

        # PATCH /api/v1/ai/contexts/:context_id/entries/:id
        def update
          authorize_action!("ai.context.update")

          entry = ::Ai::ContextPersistenceService.update_entry(
            context: @context,
            key: @entry.entry_key,
            attributes: entry_params,
            accessor: current_user,
            create_version: params[:create_version] != "false"
          )

          render_success(entry: entry.entry_details)
        rescue ::Ai::ContextPersistenceService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have write access to this context")
        end

        # DELETE /api/v1/ai/contexts/:context_id/entries/:id
        def destroy
          authorize_action!("ai.context.delete")

          ::Ai::ContextPersistenceService.delete_entry(
            context: @context,
            key: @entry.entry_key,
            accessor: current_user
          )

          render_success(message: "Entry deleted")
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have write access to this context")
        end

        # POST /api/v1/ai/contexts/:context_id/entries/:id/archive
        def archive
          authorize_action!("ai.context.update")

          @entry.archive!

          render_success(entry: @entry.reload.entry_summary)
        end

        # POST /api/v1/ai/contexts/:context_id/entries/:id/unarchive
        def unarchive
          authorize_action!("ai.context.update")

          @entry.unarchive!

          render_success(entry: @entry.reload.entry_summary)
        end

        # POST /api/v1/ai/contexts/:context_id/entries/:id/boost
        def boost
          authorize_action!("ai.context.update")

          amount = (params[:amount] || 0.1).to_f.clamp(0.01, 0.5)
          @entry.boost_importance!(amount)

          render_success(entry: @entry.reload.entry_summary)
        end

        # GET /api/v1/ai/contexts/:context_id/entries/:id/history
        def history
          authorize_action!("ai.context.read")

          versions = @entry.version_history

          render_success(
            current_version: @entry.version,
            versions: versions.map do |v|
              {
                id: v.id,
                version: v.version,
                content: v.content,
                created_at: v.created_at,
                archived_at: v.archived_at
              }
            end
          )
        end

        # POST /api/v1/ai/contexts/:context_id/entries/bulk
        def bulk_create
          authorize_action!("ai.context.create")

          entries = []
          errors = []

          (params[:entries] || []).each_with_index do |entry_data, index|
            begin
              entry = ::Ai::ContextPersistenceService.add_entry(
                context: @context,
                attributes: entry_data.permit(:key, :type, :content_text, :importance_score, :expires_at, content: {}, metadata: {}),
                accessor: current_user
              )
              entries << entry.entry_summary
            rescue StandardError => e
              errors << { index: index, error: e.message }
            end
          end

          render_success(
            created: entries,
            errors: errors,
            total: entries.count + errors.count
          )
        end

        private

        def set_context
          @context = ::Ai::ContextPersistenceService.find_context(
            account: current_account,
            context_id: params[:context_id],
            accessor: current_user
          )
        rescue ::Ai::ContextPersistenceService::NotFoundError
          render_not_found("Context")
        rescue ::Ai::ContextPersistenceService::AccessDeniedError
          render_forbidden("You don't have access to this context")
        end

        def set_entry
          @entry = @context.context_entries.find_by(id: params[:id])
          @entry ||= @context.context_entries.find_by(entry_key: params[:id])

          render_not_found("Entry") unless @entry
        end

        def entry_params
          params.require(:entry).permit(
            :key, :entry_key, :type, :entry_type, :content_text,
            :importance_score, :source_type, :source_id, :expires_at,
            content: {},
            metadata: {}
          )
        end

        def entry_filters
          {
            type: params[:type],
            source: params[:source],
            high_importance: params[:high_importance] == "true",
            include_archived: params[:include_archived] == "true"
          }.compact
        end

        def authorize_action!(permission)
          raise UnauthorizedActionError unless current_user.has_permission?(permission)
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
