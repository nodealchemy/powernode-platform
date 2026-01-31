# frozen_string_literal: true

# Plugin Marketplace Model
# Represents a collection of plugins from various sources
class PluginMarketplace < ApplicationRecord
  include Auditable
  include Searchable

  # Associations
  belongs_to :account
  belongs_to :creator, class_name: "User"
  has_many :plugins, foreign_key: :source_marketplace_id, dependent: :nullify

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :owner, presence: true, length: { maximum: 255 }
  validates :marketplace_type, inclusion: { in: %w[public private team] }
  validates :source_type, inclusion: { in: %w[git npm local url] }
  validates :visibility, inclusion: { in: %w[public private team] }

  # JSON attributes
  attribute :configuration, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :public_marketplaces, -> { where(visibility: "public") }
  scope :private_marketplaces, -> { where(visibility: "private") }
  scope :team_marketplaces, -> { where(visibility: "team") }
  scope :by_type, ->(type) { where(marketplace_type: type) }
  scope :search_by_text, ->(query) {
    where("name ILIKE ? OR description ILIKE ? OR owner ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%")
  }

  # Callbacks
  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }

  # Sync plugins from marketplace source
  def sync_plugins
    PluginMarketplaceSyncService.new(self).sync
  end

  # Update plugin count
  def update_plugin_count!
    update!(plugin_count: plugins.count)
  end

  # Update statistics
  def update_statistics!
    update!(
      average_rating: plugins.average(:average_rating)&.round(2),
      plugin_count: plugins.count
    )
  end

  private

  def generate_slug
    base_slug = name.downcase.gsub(/[^a-z0-9\s\-]/, "").gsub(/\s+/, "-").strip
    self.slug = ensure_unique_slug(base_slug)
  end

  def ensure_unique_slug(base_slug)
    return base_slug if account.nil?

    slug_candidate = base_slug
    counter = 1

    while account.plugin_marketplaces.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug_candidate
  end
end
