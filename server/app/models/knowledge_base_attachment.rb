# frozen_string_literal: true

class KnowledgeBaseAttachment < ApplicationRecord
  # Authentication

  # Concerns
  include Auditable

  # Associations
  belongs_to :article, class_name: 'KnowledgeBaseArticle', foreign_key: 'article_id'
  belongs_to :uploaded_by, class_name: 'User', foreign_key: 'uploaded_by_id'

  # Validations
  validates :filename, presence: true, length: { maximum: 255 }
  validates :content_type, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0, less_than: 50.megabytes }
  validates :file_path, presence: true
  validates :download_count, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :images, -> { where(content_type: %w[image/jpeg image/png image/gif image/webp]) }
  scope :documents, -> { where(content_type: %w[application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document]) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods
  def image?
    content_type.start_with?('image/')
  end

  def document?
    %w[application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document].include?(content_type)
  end

  def file_extension
    File.extname(filename).downcase
  end

  def human_file_size
    ActiveSupport::NumberHelper.number_to_human_size(file_size)
  end

  def record_download!
    increment!(:download_count)
  end

  def downloadable_by?(user)
    article.viewable_by?(user)
  end
end