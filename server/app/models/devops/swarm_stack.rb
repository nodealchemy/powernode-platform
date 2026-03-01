# frozen_string_literal: true

module Devops
  class SwarmStack < ApplicationRecord
    self.table_name = "devops_swarm_stacks"

    include Auditable

    STATUSES = %w[draft deploying deployed failed removing removed].freeze

    belongs_to :cluster, class_name: "Devops::SwarmCluster"
    has_many :services, class_name: "Devops::SwarmService", foreign_key: "stack_id", dependent: :nullify
    has_many :deployments, class_name: "Devops::SwarmDeployment", foreign_key: "stack_id", dependent: :nullify

    validates :name, presence: true, uniqueness: { scope: :cluster_id }
    validates :slug, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :validate_compose_file

    scope :deployed, -> { where(status: "deployed") }
    scope :draft, -> { where(status: "draft") }

    before_validation :generate_slug, on: :create

    def deployed?
      status == "deployed"
    end

    def draft?
      status == "draft"
    end

    def record_deployment!
      update!(
        status: "deployed",
        last_deployed_at: Time.current,
        deploy_count: deploy_count + 1
      )
    end

    def stack_summary
      {
        id: id,
        name: name,
        slug: slug,
        status: status,
        service_count: service_count,
        last_deployed_at: last_deployed_at,
        deploy_count: deploy_count
      }
    end

    def stack_details
      stack_summary.merge(
        compose_file: compose_file,
        compose_variables: compose_variables,
        cluster_id: cluster_id,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    private

    def generate_slug
      return if slug.present?
      return if name.blank?

      base_slug = name.parameterize
      self.slug = base_slug

      counter = 1
      while Devops::SwarmStack.where(cluster_id: cluster_id).exists?(slug: slug)
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def validate_compose_file
      return if compose_file.blank?

      begin
        YAML.safe_load(compose_file)
      rescue Psych::SyntaxError => e
        errors.add(:compose_file, "contains invalid YAML: #{e.message}")
      end
    end
  end
end
