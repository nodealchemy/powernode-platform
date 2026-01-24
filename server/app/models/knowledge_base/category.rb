# frozen_string_literal: true

module KnowledgeBase
  class Category < ApplicationRecord
    # Authentication

    # Concerns
    include Auditable
    include Searchable

    # Associations
    belongs_to :parent, class_name: "KnowledgeBase::Category", optional: true
    has_many :children, class_name: "KnowledgeBase::Category", foreign_key: "parent_id", dependent: :destroy
    has_many :articles, class_name: "KnowledgeBase::Article", foreign_key: "category_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
    validates :description, length: { maximum: 1000 }
    validates :sort_order, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :root_categories, -> { where(parent_id: nil) }
    scope :public_categories, -> { where(is_public: true) }
    scope :ordered, -> { order(:sort_order, :name) }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && slug.blank? }
    before_save :ensure_no_circular_reference

    # Methods
    def root?
      parent_id.nil?
    end

    def leaf?
      children.empty?
    end

    def path_names
      return [ name ] if root?
      parent.path_names + [ name ]
    end

    def full_path
      path_names.join(" > ")
    end

    def descendants
      children.includes(:children).flat_map { |child| [ child ] + child.descendants }
    end

    def article_count(include_descendants: false)
      if include_descendants
        all_category_ids = [ id ] + descendants.pluck(:id)
        KnowledgeBase::Article.where(category_id: all_category_ids).count
      else
        articles.count
      end
    end

    def to_tree_select_option
      {
        id: id,
        name: "#{'-' * depth} #{name}",
        level: depth
      }
    end

    private

    def generate_slug
      self.slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
    end

    def ensure_no_circular_reference
      return unless parent_id.present?

      current_parent = parent
      while current_parent
        raise StandardError, "Circular reference detected" if current_parent.id == id
        current_parent = current_parent.parent
      end
    end

    def depth
      return 0 if root?
      parent.depth + 1
    end
  end
end
