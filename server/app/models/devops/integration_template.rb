# frozen_string_literal: true

module Devops
  class IntegrationTemplate < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable
    include MarketplacePublishable

    # ==================== Table Name ====================
    self.table_name = "devops_integration_templates"

    # ==================== Constants ====================
    INTEGRATION_TYPES = %w[github_action webhook mcp_server rest_api custom].freeze
    CATEGORIES = %w[ci_cd notifications monitoring deployment security analytics testing].freeze

    # ==================== Associations ====================
    belongs_to :account, optional: true
    has_many :instances, class_name: "Devops::IntegrationInstance", foreign_key: "integration_template_id", dependent: :restrict_with_error
    has_many :subscriptions, as: :subscribable, class_name: "Marketplace::Subscription", dependent: :destroy

    # Backward compatibility alias
    def integration_instances
      instances
    end

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
    validates :integration_type, presence: true, inclusion: { in: INTEGRATION_TYPES }
    validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be semantic version (x.y.z)" }
    validates :configuration_schema, presence: true
    validate :valid_json_schemas

    # ==================== Scopes ====================
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :public_templates, -> { where(is_public: true, is_active: true) }
    scope :featured, -> { where(is_featured: true, is_public: true, is_active: true) }
    scope :by_type, ->(type) { where(integration_type: type) }
    scope :by_category, ->(category) { where(category: category) }
    scope :searchable, -> { where(is_public: true, is_active: true) }
    scope :popular, -> { order(usage_count: :desc) }
    scope :recent, -> { order(created_at: :desc) }

    # ==================== Callbacks ====================
    before_validation :generate_slug, on: :create
    before_save :sanitize_schemas

    # ==================== Class Methods ====================
    class << self
      def find_by_slug!(slug)
        find_by!(slug: slug)
      end

      def types
        INTEGRATION_TYPES
      end

      def categories
        CATEGORIES
      end
    end

    # ==================== Instance Methods ====================

    def template_summary
      {
        id: id,
        name: name,
        slug: slug,
        integration_type: integration_type,
        category: category,
        version: version,
        description: description,
        icon_url: icon_url,
        is_featured: is_featured,
        usage_count: usage_count
      }
    end

    def template_details
      template_summary.merge(
        configuration_schema: configuration_schema,
        credential_requirements: credential_requirements,
        capabilities: capabilities,
        input_schema: input_schema,
        output_schema: output_schema,
        default_configuration: default_configuration,
        documentation_url: documentation_url,
        metadata: metadata,
        supported_providers: supported_providers
      )
    end

    def validate_configuration(config)
      errors_list = []
      schema = configuration_schema

      # Validate required fields
      required_fields = schema.dig("required") || []
      required_fields.each do |field|
        errors_list << "#{field} is required" unless config.key?(field)
      end

      # Validate field types
      properties = schema.dig("properties") || {}
      properties.each do |field, spec|
        next unless config.key?(field)

        value = config[field]
        expected_type = spec["type"]

        valid = case expected_type
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Numeric)
        when "boolean" then [ true, false ].include?(value)
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        else true
        end

        errors_list << "#{field} must be a #{expected_type}" unless valid
      end

      { valid: errors_list.empty?, errors: errors_list }
    end

    def requires_credentials?
      credential_requirements.present? && credential_requirements.any?
    end

    def required_credential_type
      credential_requirements.dig("type")
    end

    def increment_usage!
      increment!(:usage_count)
    end

    def increment_install!
      increment!(:install_count)
    end

    def feature!
      update!(is_featured: true)
    end

    def unfeature!
      update!(is_featured: false)
    end

    def activate!
      update!(is_active: true)
    end

    def deactivate!
      update!(is_active: false)
    end

    def publish!
      update!(is_public: true)
    end

    def unpublish!
      update!(is_public: false)
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug

      counter = 1
      while Devops::IntegrationTemplate.exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def sanitize_schemas
      self.configuration_schema = {} if configuration_schema.blank?
      self.credential_requirements = {} if credential_requirements.blank?
      self.capabilities = [] if capabilities.blank?
      self.input_schema = {} if input_schema.blank?
      self.output_schema = {} if output_schema.blank?
      self.default_configuration = {} if default_configuration.blank?
      self.metadata = {} if metadata.blank?
      self.supported_providers = [] if supported_providers.blank?
    end

    def valid_json_schemas
      %i[configuration_schema input_schema output_schema].each do |schema_field|
        schema = send(schema_field)
        next if schema.blank?

        unless schema.is_a?(Hash)
          errors.add(schema_field, "must be a valid JSON object")
        end
      end
    end
  end
end
