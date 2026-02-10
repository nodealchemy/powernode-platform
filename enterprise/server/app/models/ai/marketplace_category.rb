# frozen_string_literal: true

module Ai
  class MarketplaceCategory < ApplicationRecord
    self.table_name = "ai_marketplace_categories"

    # Associations
    belongs_to :parent, class_name: "Ai::MarketplaceCategory", optional: true
    has_many :children, class_name: "Ai::MarketplaceCategory", foreign_key: :parent_id, dependent: :destroy

    # Validations
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :root, -> { where(parent_id: nil) }
    scope :ordered, -> { order(display_order: :asc) }

    # Callbacks
    before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

    # Methods
    def active?
      is_active
    end

    def root?
      parent_id.nil?
    end

    def has_children?
      children.any?
    end

    def ancestors
      return [] if root?

      result = []
      current = parent
      while current
        result.unshift(current)
        current = current.parent
      end
      result
    end

    def full_path
      (ancestors.map(&:name) + [ name ]).join(" > ")
    end

    def update_template_count!
      # Count templates in this category and all child categories
      category_ids = [ id ] + descendants.pluck(:id)
      count = Ai::AgentTemplate.published.where(category: category_ids.map(&:to_s)).count
      update!(template_count: count)
    end

    private

    def descendants
      children.flat_map { |child| [ child ] + child.send(:descendants) }
    end

    def generate_slug
      self.slug = name.parameterize
    end
  end
end
