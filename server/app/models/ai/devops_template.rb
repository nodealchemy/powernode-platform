# frozen_string_literal: true

module Ai
  class DevopsTemplate < ApplicationRecord
    self.table_name = "ai_devops_templates"

    # Associations
    belongs_to :account, optional: true
    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id", optional: true

    has_many :installations, class_name: "Ai::DevopsTemplateInstallation", foreign_key: :devops_template_id, dependent: :destroy

    # Validations
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
    validates :category, presence: true, inclusion: {
      in: %w[code_quality deployment documentation testing security monitoring release custom]
    }
    validates :template_type, presence: true, inclusion: {
      in: %w[code_review security_scan test_generation deployment_validation release_notes changelog api_docs coverage_analysis performance_check custom]
    }
    validates :status, presence: true, inclusion: { in: %w[draft pending_review published archived deprecated] }
    validates :visibility, presence: true, inclusion: { in: %w[private team public marketplace] }
    validates :version, presence: true

    # Scopes
    scope :published, -> { where(status: "published") }
    scope :public_templates, -> { where(visibility: %w[public marketplace]) }
    scope :system, -> { where(is_system: true) }
    scope :featured, -> { where(is_featured: true) }
    scope :by_category, ->(category) { where(category: category) }
    scope :by_type, ->(type) { where(template_type: type) }
    scope :popular, -> { order(installation_count: :desc) }
    scope :top_rated, -> { order(average_rating: :desc) }

    # Callbacks
    before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

    # Methods
    def published?
      status == "published"
    end

    def free?
      price_usd.blank? || price_usd.zero?
    end

    def publish!
      update!(status: "published", published_at: Time.current)
    end

    def archive!
      update!(status: "archived")
    end

    def deprecate!
      update!(status: "deprecated")
    end

    def increment_installations!
      increment!(:installation_count)
    end

    def validate_workflow_definition
      errors = []

      if workflow_definition.blank?
        errors << "Workflow definition is required"
        return errors
      end

      # Check for required fields
      errors << "Workflow definition must include nodes" unless workflow_definition["nodes"].is_a?(Array)
      errors << "Workflow definition must include edges" unless workflow_definition["edges"].is_a?(Array)

      errors
    end

    private

    def generate_slug
      self.slug = name.parameterize
    end
  end
end
