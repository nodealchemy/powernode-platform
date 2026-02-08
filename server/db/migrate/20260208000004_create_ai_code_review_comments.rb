# frozen_string_literal: true

class CreateAiCodeReviewComments < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_code_review_comments, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true
      t.references :task_review, foreign_key: { to_table: :ai_task_reviews }, type: :uuid, index: true
      t.references :agent, foreign_key: { to_table: :ai_agents }, type: :uuid, index: true, null: true
      t.string :file_path
      t.integer :line_start
      t.integer :line_end
      t.string :comment_type
      t.string :severity
      t.text :content
      t.text :suggested_fix
      t.string :category
      t.boolean :resolved, default: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :ai_code_review_comments, [:task_review_id, :file_path]
  end
end
