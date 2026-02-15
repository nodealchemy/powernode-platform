# frozen_string_literal: true

class DropSystemInfrastructureTables < ActiveRecord::Migration[7.2]
  def up
    drop_table :system_health_checks, if_exists: true
    drop_table :system_operations, if_exists: true
  end

  def down
    create_table :system_health_checks, id: :uuid do |t|
      t.string :check_type
      t.string :status
      t.jsonb :details, default: {}
      t.text :message
      t.float :response_time
      t.timestamps
    end

    create_table :system_operations, id: :uuid do |t|
      t.string :operation_type
      t.string :status
      t.jsonb :details, default: {}
      t.references :user, type: :uuid, foreign_key: true
      t.text :description
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
