# frozen_string_literal: true

class AddRegistryFieldsToContainerTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :devops_container_templates, :parent_template_id, :uuid
    add_column :devops_container_templates, :gitea_repo_full_name, :string
    add_column :devops_container_templates, :last_build_sha, :string
    add_column :devops_container_templates, :last_built_at, :datetime
    add_column :devops_container_templates, :webhook_secret, :string
    add_column :devops_container_templates, :auto_update, :boolean, default: true
    add_column :devops_container_templates, :featured, :boolean, default: false

    add_index :devops_container_templates, :parent_template_id
    add_index :devops_container_templates, :gitea_repo_full_name, unique: true

    add_foreign_key :devops_container_templates, :devops_container_templates,
                    column: :parent_template_id
  end
end
