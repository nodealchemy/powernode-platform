# frozen_string_literal: true

class KnowledgeBaseArticle < ApplicationRecord
  # Authentication

  # Concerns
  include Auditable
  include Searchable

  # Associations
  belongs_to :category, class_name: "KnowledgeBaseCategory"
  belongs_to :author, class_name: "User"
  has_many :article_tags, class_name: "KnowledgeBaseArticleTag", foreign_key: "article_id", dependent: :destroy
  has_many :tags, class_name: "KnowledgeBaseTag", through: :article_tags
  has_many :attachments, class_name: "KnowledgeBaseAttachment", foreign_key: "article_id", dependent: :destroy
  has_many :comments, class_name: "KnowledgeBaseComment", foreign_key: "article_id", dependent: :destroy
  has_many :article_views, class_name: "KnowledgeBaseArticleView", foreign_key: "article_id", dependent: :destroy
  has_many :workflows, class_name: "KnowledgeBaseWorkflow", foreign_key: "article_id", dependent: :destroy

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :content, presence: true
  validates :excerpt, length: { maximum: 500 }
  validates :status, inclusion: { in: %w[draft review published archived] }
  validates :sort_order, numericality: { greater_than_or_equal_to: 0 }
  validates :views_count, numericality: { greater_than_or_equal_to: 0 }
  validates :likes_count, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :published, -> { where(status: "published") }
  scope :public_articles, -> { where(is_public: true) }
  scope :featured, -> { where(is_featured: true) }
  scope :in_category, ->(category_id) { where(category_id: category_id) }
  scope :by_author, ->(author_id) { where(author_id: author_id) }
  scope :recent, -> { order(published_at: :desc) }
  scope :popular, -> { order(views_count: :desc) }
  scope :ordered, -> { order(:sort_order, :title) }
  scope :search_by_text, ->(query) {
    # Properly quote the query parameter to prevent SQL injection in ORDER clause
    quoted_query = connection.quote(query)
    where("search_vector @@ plainto_tsquery('english', ?)", query)
      .order(Arel.sql("ts_rank(search_vector, plainto_tsquery('english', #{quoted_query})) DESC"))
  }

  # Callbacks
  before_validation :generate_slug, if: -> { title.present? && slug.blank? }
  before_validation :generate_excerpt, if: -> { content.present? && excerpt.blank? }
  before_save :set_published_at, if: -> { status_changed?(to: "published") && published_at.blank? }

  # Methods
  def published?
    status == "published" && published_at.present?
  end

  def draft?
    status == "draft"
  end

  def under_review?
    status == "review"
  end

  def archived?
    status == "archived"
  end

  def viewable_by?(user)
    return true if is_public && published?
    return false unless user

    # Author can always view their own articles
    return true if author_id == user.id

    # Users with kb.manage permission can view any article
    user.permissions.include?("kb.manage")
  end

  def editable_by?(user)
    return false unless user
    return true if author_id == user.id
    user.permissions.include?("kb.manage")
  end

  def record_view!(user: nil, session_id: nil, ip_address: nil, user_agent: nil)
    # Don't record views for the author
    return if user && user.id == author_id

    # Create view record
    article_views.create!(
      user: user,
      session_id: session_id,
      ip_address: ip_address,
      user_agent: user_agent,
      viewed_at: Time.current,
      metadata: {
        recorded_at: Time.current,
        referrer: nil # Could be added later
      }
    )

    # Update view count
    increment!(:views_count)
  end

  def reading_time
    words_per_minute = 200
    word_count = content.split.size
    (word_count / words_per_minute.to_f).ceil
  end

  def tag_names
    tags.pluck(:name)
  end

  def tag_names=(names)
    self.tags = names.map do |name|
      KnowledgeBaseTag.find_or_create_by(name: name.strip) do |tag|
        tag.slug = name.strip.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-")
      end
    end
  end

  def related_articles(limit: 5)
    # Find articles with similar tags or in the same category
    related_by_tags = KnowledgeBaseArticle
      .joins(:article_tags)
      .where(knowledge_base_article_tags: { tag_id: tags.pluck(:id) })
      .where.not(id: id)
      .where(status: "published", is_public: true)
      .group("knowledge_base_articles.id")
      .order("COUNT(knowledge_base_article_tags.id) DESC")
      .limit(limit)

    related_by_category = category.articles
      .where.not(id: id)
      .where(status: "published", is_public: true)
      .order(views_count: :desc)
      .limit(limit)

    (related_by_tags + related_by_category).uniq.first(limit)
  end

  private

  def generate_slug
    base_slug = title.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
    self.slug = ensure_unique_slug(base_slug)
  end

  def ensure_unique_slug(base_slug)
    slug_candidate = base_slug
    counter = 1

    while KnowledgeBaseArticle.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug_candidate
  end

  def generate_excerpt
    # Strip HTML tags and get first 150 words
    plain_text = ActionController::Base.helpers.strip_tags(content)
    words = plain_text.split
    self.excerpt = words.first(30).join(" ") + (words.length > 30 ? "..." : "")
  end

  def set_published_at
    self.published_at = Time.current
  end
end
