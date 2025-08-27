# frozen_string_literal: true

class KnowledgeBaseArticleTag < ApplicationRecord
  # Authentication

  # Associations
  belongs_to :article, class_name: 'KnowledgeBaseArticle'
  belongs_to :tag, class_name: 'KnowledgeBaseTag'

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