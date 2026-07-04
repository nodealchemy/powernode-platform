# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Content Draft lifecycle surface (D2) — draft -> pending_review/approved/
      # rejected -> published. Creation reuses Ai::Growth::ContentDraftingService
      # (D1); publish reuses Ai::Growth::ContentPublishingService, which itself
      # reuses Ai::Growth::CrossPostService (G2) so every dispatch goes through
      # the SAME Ai::Tools::DataSourceTool approval gate every other governed
      # write already uses.
      #
      # This is a DIRECT human write surface, exactly like DataSourcesController's
      # own mutation actions (E2) and GrowthAnalyticsController#cross_post (G2):
      # hard permission-gated, no propose-instead-of-deny softening — that
      # fallback is an AGENT-context concern (see ContentPublishingService's
      # class comment), not a human REST caller's.
      class ContentDraftsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_content_draft, only: %i[show approve reject publish]
        before_action :validate_permissions

        # GET /api/v1/ai/content_drafts
        def index
          drafts = ::Ai::ContentDraft.for_account(current_account).includes(:data_source)
          drafts = drafts.where(status: params[:status]) if params[:status].present?
          drafts = drafts.for_data_source(params[:data_source_id]) if params[:data_source_id].present?
          drafts = apply_sorting(drafts)
          drafts = apply_pagination(drafts)

          render_success({
            items: drafts.map(&:draft_summary),
            pagination: pagination_data(drafts)
          })
        end

        # GET /api/v1/ai/content_drafts/:id
        def show
          render_success(draft: @content_draft.draft_summary)
        end

        # POST /api/v1/ai/content_drafts
        # body: { data_source_id:, brief:, knowledge_base_id?, brand_voice?, search_mode?, top_k? }
        def create
          service = ::Ai::Growth::ContentDraftingService.new(account: current_account, user: current_user)
          draft = service.draft(
            data_source_id: params[:data_source_id],
            brief: params[:brief],
            knowledge_base_id: params[:knowledge_base_id],
            brand_voice: params[:brand_voice],
            search_mode: params[:search_mode].presence || ::Ai::Growth::ContentDraftingService::DEFAULT_SEARCH_MODE,
            top_k: (params[:top_k].presence || ::Ai::Growth::ContentDraftingService::DEFAULT_TOP_K).to_i
          )

          render_success({ draft: draft.draft_summary }, status: :created)

          log_audit_event("ai.content_drafts.create", draft, metadata: { data_source_id: draft.ai_data_source_id })
        rescue ::Ai::Growth::ContentDraftingError, ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/content_drafts/:id/approve
        def approve
          @content_draft.approve!
          render_success(draft: @content_draft.draft_summary)

          log_audit_event("ai.content_drafts.approve", @content_draft)
        rescue ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/content_drafts/:id/reject
        def reject
          @content_draft.reject!(reason: params[:reason])
          render_success(draft: @content_draft.draft_summary)

          log_audit_event("ai.content_drafts.reject", @content_draft, metadata: { reason: params[:reason] })
        rescue ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/content_drafts/:id/publish
        # body: { additional_targets?: [{ data_source_id:, params: {} }, ...] }
        #
        # A live write dispatch (fans out to the draft's own target + any
        # additional_targets) — same bar as GrowthAnalyticsController#cross_post,
        # not a lighter read grant. No agent context on this REST path (see
        # class comment), so Ai::Tools::DataSourceTool's internal write-endpoint
        # gate is a no-op here — THIS permission check is the only gate.
        def publish
          service = ::Ai::Growth::ContentPublishingService.new(account: current_account, user: current_user)
          result = service.publish(draft: @content_draft, additional_targets: params[:additional_targets] || [])

          render_success(result)

          log_audit_event("ai.content_drafts.publish", @content_draft,
            metadata: { target_count: result[:target_count], published_count: result[:published_count],
                        proposed_count: result[:proposed_count], status: result[:status] })
        rescue ::Ai::Growth::ContentPublishingError, ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def set_content_draft
          return render_error("No account context", status: :unauthorized) unless current_account

          @content_draft = ::Ai::ContentDraft.for_account(current_account).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Content draft not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show"
            require_permission("ai.content_drafts.read")
          when "create", "approve", "reject", "publish"
            require_permission("ai.content_drafts.manage")
          end
        end
      end
    end
  end
end
