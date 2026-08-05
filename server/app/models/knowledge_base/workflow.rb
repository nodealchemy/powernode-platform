# frozen_string_literal: true

module KnowledgeBase
  # Audit trail of KnowledgeBase::Article state transitions: one row per action,
  # recording who moved an article, when, and between which statuses.
  #
  # Rows are written at the transition points themselves —
  # Api::V1::Kb::ArticlesController (#create, #update, #publish, #unpublish) and
  # Ai::Tools::KbArticleManagementTool (#create_article, #update_article) — inside
  # the same transaction as the transition, so a change that cannot be recorded
  # does not happen. See the note on blocking emission at those call sites.
  #
  # The action vocabulary is owned by the database, not by this model: the
  # `valid_kb_workflow_action` CHECK constraint on knowledge_base_workflows is
  # authoritative and VALID_ACTIONS mirrors it. Adding a value here without a
  # matching migration produces a row Postgres rejects; spec/models asserts the
  # two agree in both directions.
  class Workflow < ApplicationRecord
    # Concerns
    include Auditable

    # Article#account is optional, so fall back to the acting user.
    audit_account_via :article, :user

    # Mirrors the valid_kb_workflow_action CHECK constraint (db/schema.rb).
    # Deliberately NOT named ACTIONS: that constant already exists as
    # ActiveRecord::Callbacks::ACTIONS (%i[create destroy update]) and resolves
    # through every model, so the name silently reads as valid until shadowed.
    #
    # There is deliberately no `delete` here. Article deletions are recorded in
    # audit_logs — see Api::V1::Kb::ArticlesController#record_article_deletion!
    # — because this table structurally cannot hold them: Article declares
    # `has_many :workflows, dependent: :destroy` (article.rb:22), so a row
    # recording a deletion is cascaded away by the very act it records, while
    # an audit_logs row survives it (its `resource_id` has no foreign key).
    # The vocabulary was narrowed to match in
    # 20260805000000_narrow_kb_workflow_action_vocabulary.rb. (IMP-51b98ea3854d)
    VALID_ACTIONS = %w[create edit publish unpublish archive review].freeze

    # Article columns that say nothing about an editorial change, so they are
    # left out of the human-readable change summary.
    UNREPORTED_CHANGES = %w[id created_at updated_at search_vector].freeze

    # Associations
    belongs_to :article, class_name: "KnowledgeBase::Article"
    belongs_to :user

    # Validations
    validates :action, presence: true, inclusion: { in: VALID_ACTIONS }

    # Scopes — shaped around reading one article's history, and around asking
    # who moved anything into or out of a status (both columns are indexed).
    scope :chronological, -> { order(created_at: :asc) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_article, ->(article_id) { where(article_id: article_id) }
    scope :by_action, ->(action) { where(action: action) }
    scope :by_user, ->(user_id) { where(user_id: user_id) }
    scope :entering, ->(status) { where(to_status: status) }
    scope :leaving, ->(status) { where(from_status: status) }

    # The action naming a move from one article status to another. A change that
    # leaves the status alone is an `edit`; a move is named by where it lands,
    # except a move off `published` back to `draft`, which is an `unpublish`.
    # Restores (review/archived back to draft) have no name in the vocabulary and
    # fall back to `edit`. Always returns a member of VALID_ACTIONS.
    def self.action_for(from_status, to_status)
      return "edit" if from_status.to_s == to_status.to_s

      case to_status.to_s
      when "published" then "publish"
      when "archived"  then "archive"
      when "review"    then "review"
      when "draft"     then from_status.to_s == "published" ? "unpublish" : "edit"
      else "edit"
      end
    end

    # The one thing an `edit` row cannot say from its columns: which fields the
    # edit actually touched (from_status == to_status carries no information).
    # Reads the article's just-saved changes, so call it immediately after the
    # save — any later save on the same instance resets them.
    def self.change_summary(article)
      fields = article.saved_changes.keys - UNREPORTED_CHANGES
      return nil if fields.empty?

      "Updated: #{fields.sort.join(', ')}"
    end

    # True when this row records a status move rather than an in-place edit.
    def status_change?
      from_status != to_status
    end
  end
end
