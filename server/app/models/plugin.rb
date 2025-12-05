# frozen_string_literal: true

# Universal Plugin Model
# Supports AI providers, workflow nodes, integrations, and extensible plugin types
class Plugin < ApplicationRecord
  include Auditable
  include Searchable

  # Associations
  belongs_to :account
  belongs_to :creator, class_name: 'User'
  belongs_to :source_marketplace, class_name: 'PluginMarketplace', optional: true

  has_many :plugin_installations, dependent: :destroy
  has_one :ai_provider_plugin, dependent: :destroy
  has_many :workflow_node_plugins, dependent: :destroy
  has_many :plugin_reviews, dependent: :destroy
  has_many :plugin_dependencies, dependent: :destroy
  has_many :ai_workflow_nodes, dependent: :nullify

  # Validations
  validates :plugin_id, presence: true, uniqueness: { scope: :account_id },
            format: { with: /\A[a-z0-9\-_.]+\z/, message: 'must be lowercase with hyphens, dots, underscores only' }
  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be semantic version (x.y.z)' }
  validates :plugin_types, presence: true
  validates :status, inclusion: { in: %w[available installed error deprecated] }
  validates :source_type, inclusion: { in: %w[git npm local url marketplace] }
  validates :manifest, presence: true
  validate :validate_manifest_structure
  validate :validate_plugin_types

  # JSON attributes
  attribute :manifest, :json, default: -> { {} }
  attribute :capabilities, :json, default: -> { [] }
  attribute :configuration, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: 'available') }
  scope :installed, -> { where(status: 'installed') }
  scope :verified, -> { where(is_verified: true) }
  scope :official, -> { where(is_official: true) }
  scope :by_type, ->(type) { where('? = ANY(plugin_types)', type) }
  scope :ai_providers, -> { by_type('ai_provider') }
  scope :workflow_nodes, -> { by_type('workflow_node') }
  scope :with_capability, ->(capability) {
    where('capabilities @> ?', [capability].to_json)
  }
  scope :search_by_text, ->(query) {
    where('name ILIKE ? OR description ILIKE ? OR plugin_id ILIKE ?',
          "%#{query}%", "%#{query}%", "%#{query}%")
  }
  scope :popular, -> { order(install_count: :desc, average_rating: :desc) }
  scope :recently_updated, -> { order(updated_at: :desc) }

  # Callbacks
  before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
  after_create :create_plugin_type_records
  after_destroy :cleanup_plugin_resources

  # Plugin type checks
  def ai_provider?
    plugin_types.include?('ai_provider')
  end

  def workflow_node?
    plugin_types.include?('workflow_node')
  end

  def integration?
    plugin_types.include?('integration')
  end

  # Manifest accessors
  def manifest_version
    manifest.dig('manifest_version')
  end

  def plugin_info
    manifest.dig('plugin')
  end

  def compatibility_info
    manifest.dig('compatibility')
  end

  def permissions
    manifest.dig('permissions') || []
  end

  def lifecycle_hooks
    manifest.dig('lifecycle') || {}
  end

  # Installation management
  def install_for_account(target_account, user, configuration = {})
    PluginInstallationService.new.install_plugin(
      self,
      target_account,
      user,
      configuration
    )
  end

  def installed_for?(target_account)
    plugin_installations.where(account: target_account, status: 'active').exists?
  end

  def installation_for(target_account)
    plugin_installations.find_by(account: target_account)
  end

  # Version management
  def version_number
    Gem::Version.new(version)
  end

  def compatible_with?(powernode_version)
    return true if compatibility_info.blank?

    constraint = compatibility_info['powernode_version']
    return true if constraint.blank?

    Gem::Requirement.new(constraint).satisfied_by?(Gem::Version.new(powernode_version))
  end

  # Statistics
  def update_statistics!
    update!(
      average_rating: plugin_reviews.average(:rating)&.round(2),
      rating_count: plugin_reviews.count
    )
  end

  def increment_install_count!
    increment!(:install_count)
    increment!(:download_count)
  end

  def increment_download_count!
    increment!(:download_count)
  end

  private

  def generate_slug
    base_slug = name.downcase.gsub(/[^a-z0-9\s\-]/, '').gsub(/\s+/, '-').strip
    self.slug = ensure_unique_slug(base_slug)
  end

  def ensure_unique_slug(base_slug)
    return base_slug if account.nil?

    slug_candidate = base_slug
    counter = 1

    while account.plugins.where(slug: slug_candidate).where.not(id: id).exists?
      slug_candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug_candidate
  end

  def validate_manifest_structure
    return if manifest.blank?

    required_fields = %w[manifest_version plugin plugin_types]
    missing_fields = required_fields - manifest.keys

    if missing_fields.any?
      errors.add(:manifest, "missing required fields: #{missing_fields.join(', ')}")
    end

    # Validate plugin section
    if manifest['plugin'].present?
      plugin_required = %w[id name version]
      plugin_missing = plugin_required - manifest['plugin'].keys

      if plugin_missing.any?
        errors.add(:manifest, "plugin section missing required fields: #{plugin_missing.join(', ')}")
      end
    end
  end

  def validate_plugin_types
    return if plugin_types.blank?

    valid_types = %w[ai_provider workflow_node integration webhook tool]
    invalid_types = plugin_types - valid_types

    if invalid_types.any?
      errors.add(:plugin_types, "contains invalid types: #{invalid_types.join(', ')}")
    end
  end

  def create_plugin_type_records
    # Create AI provider plugin record if applicable
    if ai_provider? && manifest['ai_provider'].present?
      AiProviderPlugin.create!(
        plugin: self,
        provider_type: manifest['ai_provider']['provider_type'],
        supported_capabilities: manifest['ai_provider']['capabilities'] || [],
        models: manifest['ai_provider']['models'] || [],
        authentication_schema: manifest['ai_provider']['authentication'] || {},
        default_configuration: manifest['ai_provider']['configuration'] || {}
      )
    end

    # Create workflow node plugin records if applicable
    if workflow_node? && manifest['workflow_nodes'].present?
      manifest['workflow_nodes'].each do |node_config|
        WorkflowNodePlugin.create!(
          plugin: self,
          node_type: node_config['node_type'],
          node_category: node_config['category'] || 'custom',
          input_schema: node_config['input_schema'] || {},
          output_schema: node_config['output_schema'] || {},
          configuration_schema: node_config['configuration_schema'] || {},
          ui_configuration: {
            icon: node_config['icon'],
            color: node_config['color'],
            description: node_config['description']
          }
        )
      end
    end
  end

  def cleanup_plugin_resources
    # Cleanup any plugin-specific resources
    Rails.logger.info "[PLUGIN] Cleaning up resources for plugin: #{plugin_id}"
  end
end
