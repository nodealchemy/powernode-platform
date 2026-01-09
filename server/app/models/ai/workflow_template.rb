# frozen_string_literal: true

module Ai
  class WorkflowTemplate < ApplicationRecord
    self.table_name = "ai_workflow_templates"

    # Associations
    has_many :installations, class_name: "Ai::WorkflowTemplateInstallation",
             foreign_key: "ai_workflow_template_id", dependent: :destroy
    has_many :installed_workflows, through: :installations, source: :workflow
    has_many :installing_accounts, through: :installations, source: :account

    # Optional associations
    belongs_to :account, optional: true
    belongs_to :created_by_user, class_name: "User", foreign_key: :created_by_user_id, optional: true
    belongs_to :source_workflow, class_name: "Ai::Workflow", foreign_key: :source_workflow_id, optional: true

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, uniqueness: true, length: { maximum: 150 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :description, presence: true
    validates :category, presence: true, length: { maximum: 100 }
    validates :difficulty_level, presence: true, inclusion: {
      in: %w[beginner intermediate advanced expert],
      message: "must be a valid difficulty level"
    }
    validates :workflow_definition, presence: true
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (e.g., 1.0.0)" }
    validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
    validates :rating, numericality: { in: 0.0..5.0 }
    validates :rating_count, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_workflow_definition_structure

    # JSON columns
    attribute :workflow_definition, :json, default: -> { {} }
    attribute :default_variables, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }
    attribute :tags, :json, default: -> { [] }

    # Scopes
    scope :public_templates, -> { where(is_public: true) }
    scope :featured, -> { where(is_featured: true) }
    scope :published, -> { where.not(published_at: nil) }
    scope :by_category, ->(category) { where(category: category) }
    scope :by_difficulty, ->(level) { where(difficulty_level: level) }
    scope :popular, -> { order(usage_count: :desc) }
    scope :highly_rated, -> { where("rating >= ? AND rating_count >= ?", 4.0, 5) }
    scope :recently_published, -> { order(published_at: :desc) }

    # Class method for account-scoped access (includes public templates and account-owned)
    def self.accessible_to_account(account_id)
      if account_id.present? && account_id != "public"
        where(is_public: true).or(where(account_id: account_id))
      else
        where(is_public: true)
      end
    end

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_validation :normalize_tags

    # Attribute aliases for controller compatibility
    alias_attribute :template_data, :workflow_definition
    alias_attribute :install_count, :usage_count

    def visibility
      is_public? ? "public" : "private"
    end

    def visibility=(value)
      self.is_public = (value.to_s == "public")
    end

    def can_edit?(user, account)
      return false unless user && account
      return true if account_id == account.id && created_by_user_id == user.id
      user.has_permission?("ai.workflows.manage") && account_id == account.id
    end

    def can_install?(account)
      return true if is_public?
      return true if account && account_id == account.id
      false
    end

    def can_delete?(user, account)
      return false unless user && account
      return false if installations.exists? # Can't delete if there are active installations
      return true if account_id == account.id && created_by_user_id == user.id
      user.has_permission?("ai.workflows.manage") && account_id == account.id
    end

    def can_publish?(user, account)
      return false unless user && account
      return false if published? # Already published
      return true if account_id == account.id && created_by_user_id == user.id
      user.has_permission?("ai.workflows.manage") && account_id == account.id
    end

    def install_to_account(account_id:, installed_by_user_id:, **options)
      installations.create(
        account_id: account_id,
        installed_by_user_id: installed_by_user_id,
        ai_workflow_id: options[:ai_workflow_id],
        template_version: version,
        customizations: options[:custom_configuration] || {},
        metadata: { installation_notes: options[:installation_notes] }
      )
    end

    def published?
      published_at.present?
    end

    def public?
      is_public?
    end

    def featured?
      is_featured?
    end

    def available_for_installation?
      published? && public?
    end

    def workflow_nodes
      workflow_definition["nodes"] || []
    end

    def workflow_edges
      workflow_definition["edges"] || []
    end

    def workflow_variables
      workflow_definition["variables"] || []
    end

    def node_count
      workflow_nodes.size
    end

    def to_param
      slug
    end

    # Publishing methods
    def publish!
      return false if published?

      update!(is_public: true, published_at: Time.current)
    end

    def unpublish!
      return false unless published?

      update!(is_public: false, is_featured: false, published_at: nil)
    end

    def feature!
      return false unless is_public?

      update!(is_featured: true)
    end

    def unfeature!
      update!(is_featured: false)
    end

    # Rating methods
    def add_rating(new_rating)
      rating_value = new_rating.to_f
      return false if rating_value <= 0 || rating_value > 5

      new_count = rating_count + 1
      new_average = ((rating * rating_count) + rating_value) / new_count
      update!(rating: new_average.round(2), rating_count: new_count)
    end

    # Version methods
    def next_version(bump_type = :patch)
      parts = version.split(".").map(&:to_i)
      case bump_type.to_sym
      when :major
        "#{parts[0] + 1}.0.0"
      when :minor
        "#{parts[0]}.#{parts[1] + 1}.0"
      else
        "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
      end
    end

    # Complexity analysis
    def complexity_score
      score = 0
      score += workflow_nodes.size * 10
      score += workflow_edges.size * 5
      score += workflow_nodes.count { |n| n["node_type"] == "ai_agent" } * 20
      score += workflow_nodes.count { |n| n["node_type"] == "condition" } * 15
      score += workflow_nodes.count { |n| n["node_type"] == "loop" } * 15
      score
    end

    def has_ai_agents?
      workflow_nodes.any? { |n| n["node_type"] == "ai_agent" }
    end

    # Installation check
    def installed_by_account?(account)
      return false unless account
      installations.exists?(account_id: account.id)
    end

    # Export definition
    def export_definition
      {
        template: {
          name: name,
          slug: slug,
          description: description,
          category: category,
          difficulty_level: difficulty_level,
          version: version,
          tags: tags
        },
        workflow: workflow_definition,
        variables: default_variables,
        metadata: metadata
      }
    end

    # Class methods
    def self.search_by_text(query)
      return none if query.blank?

      sanitized_query = "%#{sanitize_sql_like(query)}%"
      where("name ILIKE ? OR description ILIKE ? OR slug ILIKE ?",
            sanitized_query, sanitized_query, sanitized_query)
    end

    private

    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
      self.slug = ensure_unique_slug(base_slug)
    end

    def ensure_unique_slug(base_slug)
      slug_candidate = base_slug
      counter = 1

      while self.class.where(slug: slug_candidate).where.not(id: id).exists?
        slug_candidate = "#{base_slug}-#{counter}"
        counter += 1
      end

      slug_candidate
    end

    def normalize_tags
      return unless tags.is_a?(Array)

      self.tags = tags.map(&:to_s).map(&:downcase).uniq.compact
    end

    def validate_workflow_definition_structure
      return unless workflow_definition.present?

      errors.add(:workflow_definition, "must be a hash") unless workflow_definition.is_a?(Hash)

      return unless workflow_definition.is_a?(Hash)

      %w[nodes edges].each do |required_key|
        unless workflow_definition.key?(required_key)
          errors.add(:workflow_definition, "must contain '#{required_key}' key")
        end
      end

      # Validate node structure
      nodes = workflow_definition["nodes"]
      if nodes.is_a?(Array)
        nodes.each_with_index do |node, index|
          unless node.is_a?(Hash) && node["node_id"].present? && node["node_type"].present?
            errors.add(:workflow_definition, "node at index #{index} must have 'node_id' and 'node_type'")
          end
        end
      end
    end
  end
end
