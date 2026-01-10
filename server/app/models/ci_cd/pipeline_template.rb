# frozen_string_literal: true

module CiCd
  # Template for CI/CD pipelines that can be published to the marketplace
  # Captures pipeline definitions, steps, and triggers for reuse
  class PipelineTemplate < ApplicationRecord
    include MarketplacePublishable
    include MarketplaceReviewable

    # ============================================
    # Constants
    # ============================================
    CATEGORIES = %w[review implement security deploy docs custom].freeze
    DIFFICULTY_LEVELS = %w[beginner intermediate advanced expert].freeze
    STATUSES = %w[draft published archived].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by_user, class_name: "User", foreign_key: :created_by_user_id, optional: true
    belongs_to :source_pipeline, class_name: "CiCd::Pipeline", foreign_key: :source_pipeline_id, optional: true

    # Installations tracking
    has_many :installations, class_name: "CiCd::PipelineTemplateInstallation",
             foreign_key: :ci_cd_pipeline_template_id, dependent: :destroy
    has_many :installed_pipelines, through: :installations, source: :pipeline

    # Marketplace subscriptions
    has_many :subscriptions, as: :subscribable, class_name: "Marketplace::Subscription", dependent: :destroy
    has_many :subscribing_accounts, through: :subscriptions, source: :account

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "only lowercase letters, numbers, hyphens, underscores" }
    validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
    validates :difficulty_level, inclusion: { in: DIFFICULTY_LEVELS }
    validates :status, inclusion: { in: STATUSES }
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be semantic version (x.y.z)" }
    validates :timeout_minutes, numericality: { greater_than: 0, less_than_or_equal_to: 360 }
    validates :rating, numericality: { in: 0.0..5.0 }
    validates :rating_count, numericality: { greater_than_or_equal_to: 0 }
    validates :usage_count, numericality: { greater_than_or_equal_to: 0 }
    validates :install_count, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_pipeline_definition

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(status: "published") }
    scope :draft, -> { where(status: "draft") }
    scope :archived, -> { where(status: "archived") }
    scope :public_templates, -> { where(is_public: true, status: "published") }
    scope :featured, -> { where(is_featured: true) }
    scope :by_category, ->(category) { where(category: category) }
    scope :by_difficulty, ->(level) { where(difficulty_level: level) }
    scope :popular, -> { order(usage_count: :desc) }
    scope :highly_rated, -> { where("rating >= ? AND rating_count >= ?", 4.0, 5) }
    scope :recently_published, -> { order(published_at: :desc) }
    scope :system_templates, -> { where(is_system: true) }
    scope :user_templates, -> { where(is_system: false) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_validation :set_defaults, on: :create

    # ============================================
    # Class Methods
    # ============================================
    class << self
      def accessible_to_account(account_id)
        if account_id.present?
          where(is_public: true).or(where(account_id: account_id))
        else
          where(is_public: true)
        end
      end

      def search_by_text(query)
        return none if query.blank?

        sanitized = "%#{sanitize_sql_like(query)}%"
        where("name ILIKE ? OR description ILIKE ? OR slug ILIKE ?", sanitized, sanitized, sanitized)
      end

      def create_from_pipeline(pipeline, params = {})
        template = new(
          account: pipeline.account,
          created_by_user: params[:created_by_user],
          source_pipeline: pipeline,
          name: params[:name] || "#{pipeline.name} Template",
          description: params[:description] || pipeline.description,
          category: pipeline.pipeline_type,
          pipeline_definition: extract_definition(pipeline),
          default_variables: params[:default_variables] || {},
          triggers: pipeline.triggers,
          timeout_minutes: pipeline.timeout_minutes,
          tags: params[:tags] || []
        )
        template.save!
        template
      end

      private

      def extract_definition(pipeline)
        {
          "pipeline_type" => pipeline.pipeline_type,
          "steps" => pipeline.steps.order(:position).map do |step|
            {
              "name" => step.name,
              "step_type" => step.step_type,
              "position" => step.position,
              "configuration" => step.configuration,
              "conditions" => step.conditions,
              "timeout_minutes" => step.timeout_minutes
            }
          end,
          "features" => pipeline.features,
          "runner_labels" => pipeline.runner_labels,
          "environment_variables" => pipeline.environment_variables
        }
      end
    end

    # ============================================
    # Instance Methods
    # ============================================

    def published?
      status == "published" && published_at.present?
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

    def can_edit?(user, account)
      return false unless user && account
      return true if account_id == account.id && created_by_user_id == user.id
      user.has_permission?("ai.workflows.manage") && account_id == account.id
    end

    def can_install?(account)
      return true if is_public? && published?
      return true if account && account_id == account.id
      false
    end

    def can_delete?(user, account)
      return false unless user && account
      return false if installations.exists?
      return true if account_id == account.id && created_by_user_id == user.id
      user.has_permission?("ai.workflows.manage") && account_id == account.id
    end

    # Publishing methods
    def publish!
      return false if published?

      update!(status: "published", is_public: true, published_at: Time.current)
    end

    def unpublish!
      return false unless published?

      update!(status: "draft", is_public: false, is_featured: false, published_at: nil)
    end

    def archive!
      update!(status: "archived")
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
      when :major then "#{parts[0] + 1}.0.0"
      when :minor then "#{parts[0]}.#{parts[1] + 1}.0"
      else "#{parts[0]}.#{parts[1]}.#{parts[2] + 1}"
      end
    end

    # Pipeline definition accessors
    def steps_definition
      pipeline_definition["steps"] || []
    end

    def step_count
      steps_definition.size
    end

    def features
      pipeline_definition["features"] || {}
    end

    def runner_labels
      pipeline_definition["runner_labels"] || []
    end

    def to_param
      slug
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
        pipeline: pipeline_definition,
        variables: default_variables,
        triggers: triggers,
        metadata: metadata
      }
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

    def set_defaults
      self.status ||= "draft"
      self.difficulty_level ||= "intermediate"
      self.version ||= "1.0.0"
      self.timeout_minutes ||= 30
      self.pipeline_definition ||= {}
      self.default_variables ||= {}
      self.triggers ||= {}
      self.tags ||= []
      self.metadata ||= {}
    end

    def validate_pipeline_definition
      return unless pipeline_definition.present?
      return if pipeline_definition.is_a?(Hash)

      errors.add(:pipeline_definition, "must be a valid JSON object")
    end
  end
end
