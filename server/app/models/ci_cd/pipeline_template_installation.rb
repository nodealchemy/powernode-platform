# frozen_string_literal: true

module CiCd
  class PipelineTemplateInstallation < ApplicationRecord
    # ============================================
    # Associations
    # ============================================
    belongs_to :template, class_name: "CiCd::PipelineTemplate",
               foreign_key: :ci_cd_pipeline_template_id
    belongs_to :account
    belongs_to :installed_by_user, class_name: "User",
               foreign_key: :installed_by_user_id, optional: true
    belongs_to :pipeline, class_name: "CiCd::Pipeline",
               foreign_key: :ci_cd_pipeline_id, optional: true

    # ============================================
    # Validations
    # ============================================
    validates :template, presence: true
    validates :account, presence: true
    validates :template, uniqueness: { scope: :account_id,
              message: "already installed for this account" }

    # ============================================
    # Callbacks
    # ============================================
    after_create :increment_template_install_count

    private

    def increment_template_install_count
      template.increment!(:install_count)
    end
  end
end
