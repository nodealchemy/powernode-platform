# frozen_string_literal: true

module KnowledgeBase
  class Attachment < ApplicationRecord
    # Authentication

    # Concerns
    include Auditable

    # Associations
    belongs_to :article, class_name: "KnowledgeBase::Article", foreign_key: "article_id"
    belongs_to :uploaded_by, class_name: "User", foreign_key: "uploaded_by_id"

    # Validations
    validates :filename, presence: true, length: { maximum: 255 }
    validates :content_type, presence: true
    validates :file_size, presence: true, numericality: { greater_than: 0, less_than: 50.megabytes }
    validates :file_path, presence: true
    validates :download_count, numericality: { greater_than_or_equal_to: 0 }

    # File upload handling
    attr_accessor :file

    # Callbacks
    before_create :process_file_upload, if: -> { file.present? }

    # Scopes
    scope :images, -> { where(content_type: %w[image/jpeg image/png image/gif image/webp]) }
    scope :documents, -> { where(content_type: %w[application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document]) }
    scope :recent, -> { order(created_at: :desc) }

    # Methods
    def image?
      content_type.start_with?("image/")
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

    def file_url
      return nil unless file_path.present?

      # For local development, return a full URL
      if Rails.env.development?
        Rails.application.routes.url_helpers.rails_blob_path(file_path, only_path: false)
      else
        # For production, you might use a CDN or cloud storage URL
        "/uploads/kb/#{file_path}"
      end
    end

    private

    def process_file_upload
      return unless file.present?

      # Create upload directory if it doesn't exist
      upload_dir = Rails.root.join("public", "uploads", "kb")
      FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)

      # Generate unique filename
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      unique_filename = "#{timestamp}_#{SecureRandom.hex(8)}_#{filename}"

      # Save file to disk
      file_full_path = upload_dir.join(unique_filename)
      File.open(file_full_path, "wb") do |f|
        f.write(file.read)
      end

      # Store relative path in database
      self.file_path = unique_filename
      self.file_size = file.size
      self.content_type = file.content_type
      self.filename = file.original_filename
    end
  end
end

# Backward compatibility alias
KnowledgeBaseAttachment = KnowledgeBase::Attachment
