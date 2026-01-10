# frozen_string_literal: true

class CreateCiCdPipelineTemplateInstallations < ActiveRecord::Migration[7.2]
  def change
    create_table :ci_cd_pipeline_template_installations, id: :uuid do |t|
      t.uuid :ci_cd_pipeline_template_id, null: false
      t.uuid :account_id, null: false
      t.uuid :installed_by_user_id
      t.uuid :ci_cd_pipeline_id  # The pipeline created from template

      t.string :template_version  # Version at time of installation
      t.jsonb :customizations, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ci_cd_pipeline_template_installations, :ci_cd_pipeline_template_id, name: "idx_cicd_template_installations_template"
    add_index :ci_cd_pipeline_template_installations, :account_id, name: "idx_cicd_template_installations_account"
    add_index :ci_cd_pipeline_template_installations, :ci_cd_pipeline_id, name: "idx_cicd_template_installations_pipeline"
    add_index :ci_cd_pipeline_template_installations, [:ci_cd_pipeline_template_id, :account_id], name: "idx_cicd_template_installations_unique"
  end
end
