# frozen_string_literal: true

module KnowledgeBase
  class Comment < ApplicationRecord
    # Authentication

    # Concerns
    include Auditable

    # Associations
    belongs_to :article, class_name: "KnowledgeBase::Article", foreign_key: "article_id"
    belongs_to :author, class_name: "User", foreign_key: "author_id"
    belongs_to :parent, class_name: "KnowledgeBase::Comment", optional: true
    has_many :replies, class_name: "KnowledgeBase::Comment", foreign_key: "parent_id", dependent: :destroy

    # Validations
    validates :content, presence: true, length: { maximum: 2000 }
    validates :status, inclusion: { in: %w[pending approved rejected spam] }
    validates :likes_count, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :approved, -> { where(status: "approved") }
    scope :pending, -> { where(status: "pending") }
    scope :top_level, -> { where(parent_id: nil) }
    scope :replies_to, ->(comment_id) { where(parent_id: comment_id) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_create :set_default_status

    # Methods
    def approved?
      status == "approved"
    end

    def pending?
      status == "pending"
    end

    def rejected?
      status == "rejected"
    end

    def spam?
      status == "spam"
    end

    def reply?
      parent_id.present?
    end

    def top_level?
      parent_id.nil?
    end

    def approve!
      update!(status: "approved")
    end

    def reject!
      update!(status: "rejected")
    end

    def mark_as_spam!
      update!(status: "spam")
    end

    def can_be_moderated_by?(moderator)
      return false unless moderator
      moderator.permissions.include?("kb.manage")
    end

    def replies_count
      replies.approved.count
    end

    private

    def set_default_status
      # Auto-approve comments from users with kb.edit permission
      if author.permissions.include?("kb.manage") || author.permissions.include?("kb.edit")
        self.status = "approved"
      else
        self.status = "pending"
      end
    end
  end
end

# Backward compatibility alias
KnowledgeBaseComment = KnowledgeBase::Comment
