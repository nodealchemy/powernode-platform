# frozen_string_literal: true

module KnowledgeBase
  class Tag < ApplicationRecord
    # Authentication

    # Concerns
    include Auditable

    # Associations
    has_many :article_tags, class_name: "KnowledgeBase::ArticleTag", foreign_key: "tag_id", dependent: :destroy
    has_many :articles, class_name: "KnowledgeBase::Article", through: :article_tags

    # Validations
    validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 100 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
    validates :description, length: { maximum: 500 }
    validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }
    validates :usage_count, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :popular, -> { where("usage_count > 0").order(usage_count: :desc) }
    scope :alphabetical, -> { order(:name) }
    scope :by_color, ->(color) { where(color: color) }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && slug.blank? }
    before_validation :normalize_name
    before_validation :ensure_color

    # Methods
    def increment_usage!
      increment!(:usage_count)
    end

    def decrement_usage!
      return if usage_count <= 0
      decrement!(:usage_count)
    end

    def popular?
      usage_count > 5
    end

    def to_badge_data
      {
        id: id,
        name: name,
        slug: slug,
        color: color,
        usage_count: usage_count
      }
    end

    private

    def generate_slug
      self.slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
    end

    def normalize_name
      self.name = name.strip.titleize if name.present?
    end

    def ensure_color
      self.color = "#3B82F6" if color.blank?
    end
  end
end

# Backward compatibility alias
KnowledgeBaseTag = KnowledgeBase::Tag
