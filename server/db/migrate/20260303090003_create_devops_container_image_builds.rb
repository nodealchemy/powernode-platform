# frozen_string_literal: true

class CreateDevopsContainerImageBuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :devops_container_image_builds, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :container_template, type: :uuid, null: false,
                   foreign_key: { to_table: :devops_container_templates }
      t.string :trigger_type, null: false
      t.string :status, default: "pending"
      t.string :git_sha
      t.string :image_tag
      t.string :gitea_workflow_run_id
      t.references :triggered_by_build, type: :uuid,
                   foreign_key: { to_table: :devops_container_image_builds }
      t.text :build_log
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
