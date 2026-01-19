# frozen_string_literal: true

module Devops
  # Join table connecting pipelines to repositories
  # Allows repository-specific overrides for pipeline configurations
  class PipelineRepository < ApplicationRecord
    # ============================================
    # Associations
    # ============================================
    belongs_to :pipeline, class_name: 'Devops::Pipeline', foreign_key: :ci_cd_pipeline_id
    belongs_to :repository, class_name: 'Devops::Repository', foreign_key: :ci_cd_repository_id

    # ============================================
    # Validations
    # ============================================
    validates :devops_repository_id, uniqueness: { scope: :ci_cd_pipeline_id }

    # ============================================
    # Instance Methods
    # ============================================

    def effective_configuration
      pipeline_config = pipeline.attributes.slice('triggers', 'environment', 'features')
      pipeline_config.deep_merge(overrides || {})
    end

    def override_value(key)
      overrides.dig(key.to_s)
    end

    def has_override?(key)
      overrides.key?(key.to_s)
    end

    def account
      pipeline.account
    end
  end
end
