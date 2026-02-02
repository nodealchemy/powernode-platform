# frozen_string_literal: true

module SupplyChain
  class ScanTemplate < ApplicationRecord
    include Auditable
    include MarketplacePublishable

    self.table_name = "supply_chain_scan_templates"

    # ============================================
    # Constants
    # ============================================
    CATEGORIES = %w[security compliance license quality custom].freeze
    STATUSES = %w[draft published archived deprecated].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account, optional: true
    belongs_to :created_by, class_name: "User", optional: true

    has_many :scan_instances, class_name: "SupplyChain::ScanInstance",
             foreign_key: :scan_template_id, dependent: :restrict_with_error

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9\-]+\z/, message: "only lowercase letters, numbers, and hyphens" }
    validates :category, presence: true, inclusion: { in: CATEGORIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :version, presence: true
    validates :average_rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
    validates :install_count, numericality: { greater_than_or_equal_to: 0 }

    # ============================================
    # Scopes
    # ============================================
    scope :system_templates, -> { where(is_system: true) }
    scope :custom_templates, -> { where(is_system: false) }
    scope :public_templates, -> { where(is_public: true) }
    scope :private_templates, -> { where(is_public: false) }
    scope :published, -> { where(status: "published") }
    scope :draft, -> { where(status: "draft") }
    scope :archived, -> { where(status: "archived") }
    scope :by_category, ->(category) { where(category: category) }
    scope :security_templates, -> { where(category: "security") }
    scope :compliance_templates, -> { where(category: "compliance") }
    scope :license_templates, -> { where(category: "license") }
    scope :popular, -> { order(install_count: :desc) }
    scope :top_rated, -> { order(average_rating: :desc) }
    scope :for_ecosystem, ->(eco) { where("supported_ecosystems @> ?", [ eco ].to_json) }
    scope :available_for_account, ->(account) { where(is_public: true).or(where(account_id: account.id)).or(system_templates) }
    scope :alphabetical, -> { order(name: :asc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def system?
      is_system
    end

    def custom?
      !is_system
    end

    def public?
      is_public
    end

    def private?
      !is_public
    end

    def published?
      status == "published"
    end

    def draft?
      status == "draft"
    end

    def archived?
      status == "archived"
    end

    def deprecated?
      status == "deprecated"
    end

    def security?
      category == "security"
    end

    def compliance?
      category == "compliance"
    end

    def license?
      category == "license"
    end

    def supports_ecosystem?(ecosystem)
      return false if supported_ecosystems.nil?

      supported_ecosystems.include?(ecosystem)
    end

    def ecosystem_count
      supported_ecosystems&.length || 0
    end

    def publish!
      update!(status: "published", is_public: true)
    end

    def unpublish!
      update!(status: "draft", is_public: false)
    end

    def archive!
      update!(status: "archived")
    end

    def deprecate!
      update!(status: "deprecated")
    end

    def increment_install_count!
      increment!(:install_count)
    end

    def update_rating!(new_rating)
      # Calculate new average rating
      total_reviews = install_count > 0 ? install_count : 1
      new_average = ((average_rating * (total_reviews - 1)) + new_rating) / total_reviews
      update!(average_rating: new_average.round(2))
    end

    def install_for_account!(account, installed_by: nil, config: {})
      # Ensure both configs have symbol keys for consistent merging
      base_config = default_configuration.is_a?(Hash) ? default_configuration.symbolize_keys : {}
      new_config = config.is_a?(Hash) ? config.symbolize_keys : {}
      merged_config = base_config.deep_merge(new_config)

      scan_instances.create!(
        account: account,
        installed_by: installed_by,
        name: name,
        configuration: merged_config,
        status: "active"
      ).tap { increment_install_count! }
    end

    def validate_configuration(config)
      return { valid: true, errors: [] } if configuration_schema.blank?

      errors = []
      schema = configuration_schema.with_indifferent_access
      config_with_access = config.with_indifferent_access

      # Check required fields
      (schema[:required] || []).each do |field|
        errors << "Missing required field: #{field}" unless config_with_access.key?(field)
      end

      # Check field types
      (schema[:properties] || {}).each do |field, field_schema|
        next unless config_with_access.key?(field)

        value = config_with_access[field]
        expected_type = field_schema[:type]

        type_valid = case expected_type
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Numeric)
        when "boolean" then value.in?([ true, false ])
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        else true
        end

        errors << "Field #{field} must be of type #{expected_type}" unless type_valid

        # Check enum values
        if field_schema[:enum].present? && !field_schema[:enum].include?(value)
          errors << "Field #{field} must be one of: #{field_schema[:enum].join(', ')}"
        end
      end

      { valid: errors.empty?, errors: errors }
    end

    def summary
      {
        id: id,
        name: name,
        slug: slug,
        description: description,
        category: category,
        status: status,
        version: version,
        is_system: is_system,
        is_public: is_public,
        supported_ecosystems: supported_ecosystems,
        install_count: install_count,
        average_rating: average_rating,
        created_at: created_at
      }
    end

    def full_details
      {
        summary: summary,
        configuration_schema: configuration_schema,
        default_configuration: default_configuration
      }
    end

    private

    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      self.slug = base_slug

      counter = 1
      while self.class.where(slug: slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def sanitize_jsonb_fields
      self.configuration_schema ||= {}
      self.default_configuration ||= {}
      self.supported_ecosystems ||= []
      self.metadata ||= {}
    end
  end
end
