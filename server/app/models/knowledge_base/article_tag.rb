# frozen_string_literal: true

module KnowledgeBase
  class ArticleTag < ApplicationRecord
    # Authentication

    # Associations
    belongs_to :article, class_name: "KnowledgeBase::Article"
    belongs_to :tag, class_name: "KnowledgeBase::Tag"

    # Validations
    validates :article_id, uniqueness: { scope: :tag_id }

    # Callbacks
    after_create :increment_tag_usage
    after_destroy :decrement_tag_usage

    private

    def increment_tag_usage
      tag.increment_usage!
    end

    def decrement_tag_usage
      tag.decrement_usage!
    end
  end
end
