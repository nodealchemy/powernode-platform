# frozen_string_literal: true

module Marketplace
  class Feature < ApplicationRecord
    include AuditLogging

    # Constants
    FEATURE_TYPES = %w[toggle quota permission integration api_access ui_component].freeze

    # Associations
    belongs_to :app, class_name: "Marketplace::Definition", foreign_key: "app_id"
    has_many :dependent_features, class_name: "Marketplace::Feature", foreign_key: "dependency_id"

    # Validations
    validates :name, presence: true, length: { minimum: 2, maximum: 255 }
    validates :slug, presence: true, uniqueness: { scope: :app_id }
    validates :feature_type, presence: true, inclusion: { in: FEATURE_TYPES }
    validates :description, length: { maximum: 1000 }

    # JSON validations - allow default empty values
    validate :configuration_is_valid_json
    validate :dependencies_is_valid_array

    # Scopes
    scope :enabled_by_default, -> { where(default_enabled: true) }
    scope :disabled_by_default, -> { where(default_enabled: false) }
    scope :by_type, ->(type) { where(feature_type: type) }
    scope :toggles, -> { where(feature_type: "toggle") }
    scope :quotas, -> { where(feature_type: "quota") }
    scope :permissions, -> { where(feature_type: "permission") }
    scope :integrations, -> { where(feature_type: "integration") }
    scope :api_access, -> { where(feature_type: "api_access") }
    scope :ui_components, -> { where(feature_type: "ui_component") }
    scope :root_features, -> { where("dependencies = '[]'::jsonb") }

    # Callbacks
    before_validation :generate_slug, if: :name_changed?
    before_save :validate_dependencies_exist
    before_save :prevent_circular_dependencies
    after_create :log_feature_creation
    after_update :log_feature_updates
    before_destroy :check_usage_in_plans

    # Type checking methods
    def toggle?
      feature_type == "toggle"
    end

    def quota?
      feature_type == "quota"
    end

    def permission?
      feature_type == "permission"
    end

    def integration?
      feature_type == "integration"
    end

    def api_access?
      feature_type == "api_access"
    end

    def ui_component?
      feature_type == "ui_component"
    end

    # Dependency methods
    def has_dependencies?
      dependencies.any?
    end

    def dependency_features
      return Marketplace::Feature.none if dependencies.empty?

      app.features.where(slug: dependencies)
    end

    def add_dependency(feature_slug)
      return false unless app.features.exists?(slug: feature_slug)
      return false if feature_slug == slug # Can't depend on itself

      self.dependencies = (dependencies + [feature_slug.to_s]).uniq
      save
    end

    def remove_dependency(feature_slug)
      self.dependencies = dependencies - [feature_slug.to_s]
      save
    end

    def can_be_enabled_with?(enabled_features)
      return true unless has_dependencies?

      (dependencies - enabled_features.map(&:to_s)).empty?
    end

    def dependent_features_list
      app.features.where("dependencies @> ?", [slug].to_json)
    end

    # Configuration methods
    def get_config(key)
      configuration[key.to_s]
    end

    def set_config(key, value)
      self.configuration = configuration.merge(key.to_s => value)
      save
    end

    def merge_config(new_config)
      self.configuration = configuration.merge(new_config.stringify_keys)
      save
    end

    # Feature-type specific methods
    def quota_limit
      return nil unless quota?

      get_config("limit")
    end

    def quota_period
      return nil unless quota?

      get_config("period") || "monthly"
    end

    def quota_reset_day
      return nil unless quota?

      get_config("reset_day") || 1
    end

    def required_permission
      return nil unless permission?

      get_config("permission")
    end

    def integration_provider
      return nil unless integration?

      get_config("provider")
    end

    def integration_config
      return {} unless integration?

      get_config("integration_config") || {}
    end

    def api_endpoints
      return [] unless api_access?

      get_config("endpoints") || []
    end

    def api_methods
      return [] unless api_access?

      get_config("methods") || ["GET"]
    end

    def ui_component_name
      return nil unless ui_component?

      get_config("component")
    end

    def ui_component_props
      return {} unless ui_component?

      get_config("props") || {}
    end

    # Usage tracking
    def used_in_plans
      app.plans.where("features @> ?", [slug].to_json)
    end

    def usage_count
      used_in_plans.count
    end

    def active_usage_count
      used_in_plans.active.count
    end

    def subscriber_count
      used_in_plans.joins(:subscriptions)
                   .where(app_subscriptions: { status: "active" })
                   .count
    end

    # Enable/disable methods
    def enable_by_default!
      update!(default_enabled: true)
      log_default_enabled
    end

    def disable_by_default!
      update!(default_enabled: false)
      log_default_disabled
    end

    # Clone method
    def duplicate(new_name = nil)
      new_feature = dup
      new_feature.name = new_name || "#{name} (Copy)"
      new_feature.slug = nil # Will be regenerated
      new_feature.default_enabled = false
      new_feature.dependencies = dependencies.dup
      new_feature.configuration = configuration.dup
      new_feature.save
      new_feature
    end

    # Validation helpers
    def validate_for_plan(plan)
      errors = []

      # Check if all dependencies are enabled in the plan
      if has_dependencies?
        missing_deps = dependencies - plan.features
        if missing_deps.any?
          errors << "Missing required dependencies: #{missing_deps.join(', ')}"
        end
      end

      # Type-specific validations
      case feature_type
      when "quota"
        errors << "Quota limit must be specified" unless quota_limit
      when "permission"
        errors << "Required permission must be specified" unless required_permission
      when "integration"
        errors << "Integration provider must be specified" unless integration_provider
      when "api_access"
        errors << "API endpoints must be specified" unless api_endpoints.any?
      when "ui_component"
        errors << "UI component name must be specified" unless ui_component_name
      end

      errors
    end

    private

    def generate_slug
      return if slug.present? && !name_changed?

      base_slug = name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/_+/, "_").gsub(/^_+|_+$/, "")
      candidate_slug = base_slug
      counter = 1

      while app.features.exists?(slug: candidate_slug)
        candidate_slug = "#{base_slug}_#{counter}"
        counter += 1
      end

      self.slug = candidate_slug
    end

    def validate_dependencies_exist
      return if dependencies.empty?

      existing_features = app.features.where.not(id: id).pluck(:slug)
      invalid_dependencies = dependencies - existing_features

      if invalid_dependencies.any?
        errors.add(:dependencies, "contains non-existent features: #{invalid_dependencies.join(', ')}")
        throw :abort
      end
    end

    def prevent_circular_dependencies
      return if dependencies.empty?

      if would_create_circular_dependency?
        errors.add(:dependencies, "would create circular dependency")
        throw :abort
      end
    end

    def would_create_circular_dependency?
      return false if dependencies.empty?

      # Build dependency graph and check for cycles
      visited = Set.new
      rec_stack = Set.new

      def has_cycle(current_slug, visited, rec_stack, all_features_deps)
        return false if visited.include?(current_slug)

        visited.add(current_slug)
        rec_stack.add(current_slug)

        deps = all_features_deps[current_slug] || []
        deps.each do |dep_slug|
          if !visited.include?(dep_slug) && has_cycle(dep_slug, visited, rec_stack, all_features_deps)
            return true
          elsif rec_stack.include?(dep_slug)
            return true
          end
        end

        rec_stack.delete(current_slug)
        false
      end

      # Get all feature dependencies including this one
      all_deps = {}
      app.features.where.not(id: id).each do |feature|
        all_deps[feature.slug] = feature.dependencies
      end
      all_deps[slug] = dependencies

      has_cycle(slug, visited, rec_stack, all_deps)
    end

    def check_usage_in_plans
      if used_in_plans.any?
        errors.add(:base, "Cannot delete feature that is used in #{usage_count} plan(s)")
        throw :abort
      end
    end

    def log_feature_creation
      Rails.logger.info "Marketplace::Feature created: #{name} (#{id}) for #{app.name}"
    end

    def log_feature_updates
      return unless saved_changes.any?

      Rails.logger.info "Marketplace::Feature updated: #{name} (#{id}) - Changes: #{saved_changes.keys.join(', ')}"
    end

    def log_default_enabled
      Rails.logger.info "Marketplace::Feature enabled by default: #{name} (#{id})"
    end

    def log_default_disabled
      Rails.logger.info "Marketplace::Feature disabled by default: #{name} (#{id})"
    end

    def configuration_is_valid_json
      return if configuration.nil?
      unless configuration.is_a?(Hash)
        errors.add(:configuration, "must be a valid JSON object")
      end
    end

    def dependencies_is_valid_array
      return if dependencies.nil?
      unless dependencies.is_a?(Array)
        errors.add(:dependencies, "must be a valid JSON array")
      end
    end
  end
end
