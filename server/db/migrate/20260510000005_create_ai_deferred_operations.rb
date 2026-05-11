# frozen_string_literal: true

class CreateAiDeferredOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_deferred_operations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :approval_request, type: :uuid, null: true,
                                       foreign_key: { to_table: :ai_approval_requests }
      t.references :requested_by, type: :uuid, null: true,
                                   foreign_key: { to_table: :users }
      t.references :ai_agent, type: :uuid, null: true,
                               foreign_key: { to_table: :ai_agents }

      t.string  :action_category, null: false
      t.string  :executor_class,  null: false
      t.string  :status, null: false, default: "pending"
      t.jsonb   :params,  null: false, default: {}
      t.jsonb   :result,  null: false, default: {}
      t.text    :error_message
      t.string  :source_type
      t.uuid    :source_id
      t.text    :description
      t.datetime :executed_at

      t.timestamps
    end

    add_index :ai_deferred_operations, [:account_id, :status]
    add_index :ai_deferred_operations, [:source_type, :source_id]
    add_index :ai_deferred_operations, :action_category
    add_index :ai_deferred_operations, :executor_class
  end
end
