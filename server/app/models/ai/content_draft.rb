# frozen_string_literal: true

module Ai
  # A reviewable draft of provider-ready content (D1), generated from a
  # knowledge base + brand-voice profile by Ai::Growth::ContentDraftingService.
  # Created with status "draft" and NEVER auto-published — D2 owns advancing
  # a draft through pending_review/approved/rejected/published and the actual
  # dispatch (through the same governed write path Ai::Growth::CrossPostService
  # already uses).
  class ContentDraft < ApplicationRecord
    self.table_name = "ai_content_drafts"

    include Auditable

    STATUSES = %w[draft pending_review approved rejected published].freeze

    # D2 lifecycle transitions — see Api::V1::Ai::ContentDraftsController
    # #approve/#reject. The actual dispatch (draft -> published) is NOT a
    # simple status flip; it is owned by Ai::Growth::ContentPublishingService,
    # which only advances status after a real (or proposed) publish attempt.
    APPROVABLE_FROM = %w[draft pending_review].freeze
    REJECTABLE_FROM = %w[draft pending_review approved].freeze

    # Associations
    belongs_to :account
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    belongs_to :knowledge_base, class_name: "Ai::KnowledgeBase", foreign_key: "ai_knowledge_base_id", optional: true
    belongs_to :requesting_agent, class_name: "Ai::Agent", foreign_key: "requesting_agent_id", optional: true
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    # JSON column defaults (lambda required for mutable defaults)
    attribute :segments, :json, default: -> { [] }
    attribute :brand_voice, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Validations
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :source_type, presence: true
    validates :content, presence: true

    # Scopes
    scope :for_account, ->(account) { where(account_id: account.is_a?(Account) ? account.id : account) }
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :reviewable, -> { where(status: %w[draft pending_review]) }
    scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

    # True when the drafted content was split into a multi-post thread
    # (segments.size > 1) rather than a single post.
    def thread?
      segments.size > 1
    end

    # Human-review approval — does NOT publish. A separate step from
    # ContentPublishingService#publish so a draft can be marked reviewed
    # before (or without) actually dispatching it.
    def approve!
      raise ArgumentError, "cannot approve draft #{id} from status '#{status}'" unless APPROVABLE_FROM.include?(status)

      update!(status: "approved")
    end

    # Terminal — a rejected draft can never be published (ContentPublishingService
    # hard-refuses any TERMINAL_STATUSES draft, rejected included).
    def reject!(reason: nil)
      raise ArgumentError, "cannot reject draft #{id} from status '#{status}'" unless REJECTABLE_FROM.include?(status)

      update!(status: "rejected", metadata: metadata.merge("rejected_reason" => reason).compact)
    end

    def draft_summary
      {
        id: id,
        data_source_id: ai_data_source_id,
        source_type: source_type,
        status: status,
        content: content,
        segments: segments,
        thread: thread?,
        char_count: content.to_s.length,
        created_at: created_at.iso8601
      }
    end
  end
end
