# frozen_string_literal: true

class Page < ApplicationRecord
  # Associations
  belongs_to :user, foreign_key: "author_id"

  # Polymorphic association to file objects (images attached to this page)
  has_many :file_objects, as: :attachable, dependent: :nullify
  has_many :images, -> { where(file_type: "image") }, as: :attachable, class_name: "FileObject"

  # Alias method for better readability
  def author
    user
  end

  def author=(user_obj)
    self.user = user_obj
  end

  # Validations
  validates :title, presence: true, length: { minimum: 1, maximum: 200 }
  validates :slug, presence: true, uniqueness: true, length: { minimum: 1, maximum: 150 }
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: %w[draft published] }
  validates :meta_description, length: { maximum: 300 }, allow_blank: true
  validates :meta_keywords, length: { maximum: 500 }, allow_blank: true
  validate :slug_format

  # Callbacks
  before_validation :generate_slug_if_blank, on: :create
  before_validation :sanitize_slug
  before_save :set_published_at

  # Scopes
  scope :published, -> { where(status: "published") }
  scope :draft, -> { where(status: "draft") }
  scope :by_slug, ->(slug) { where(slug: slug) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_author, ->(author) { where(author_id: author.id) }

  # Instance methods
  def published?
    status == "published"
  end

  def draft?
    status == "draft"
  end

  def publish!
    update!(status: "published", published_at: Time.current)
  end

  def unpublish!
    update!(status: "draft", published_at: nil)
  end

  def to_param
    slug
  end

  def rendered_content
    PageService.render_markdown(content)
  end

  def word_count
    content.to_s.split.length
  end

  def estimated_read_time
    # Average reading speed: 200 words per minute
    (word_count / 200.0).ceil
  end

  def seo_title
    title
  end

  def seo_description
    meta_description.present? ? meta_description : content.to_s.truncate(160)
  end

  def seo_keywords_array
    return [] if meta_keywords.blank?
    meta_keywords.split(",").map(&:strip).reject(&:blank?)
  end

  private

  def generate_slug_if_blank
    return if title.blank?
    if slug.blank?
      self.slug = PageService.generate_slug(title)
    end
  end

  def sanitize_slug
    return if slug.blank?
    # Don't sanitize if we're in the middle of validation
    unless @validating_slug
      self.slug = PageService.sanitize_slug(slug)
    end
  end

  def slug_format
    return if slug.blank?

    @validating_slug = true

    unless slug.match?(/\A[a-z0-9\-]+\z/)
      errors.add(:slug, "can only contain lowercase letters, numbers, and hyphens")
    end

    if slug.starts_with?("-") || slug.ends_with?("-")
      errors.add(:slug, "cannot start or end with a hyphen")
    end

    if slug.include?("--")
      errors.add(:slug, "cannot contain consecutive hyphens")
    end

    @validating_slug = false
  end

  def set_published_at
    if status_changed? && status == "published" && published_at.blank?
      self.published_at = Time.current
    elsif status_changed? && status == "draft"
      self.published_at = nil
    end
  end
end
