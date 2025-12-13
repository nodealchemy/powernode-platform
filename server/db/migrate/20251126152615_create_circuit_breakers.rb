# frozen_string_literal: true

class CreateCircuitBreakers < ActiveRecord::Migration[7.1]
  def change
    create_table :circuit_breakers, id: :uuid do |t|
      t.string :name, null: false
      t.string :service, null: false
      t.string :provider
      t.string :state, null: false, default: 'closed'
      t.integer :failure_count, default: 0
      t.integer :failure_threshold, null: false, default: 5
      t.integer :success_count, default: 0
      t.integer :success_threshold, null: false, default: 2
      t.integer :timeout_seconds, default: 30
      t.integer :reset_timeout_seconds, default: 60
      t.jsonb :configuration, default: {}
      t.jsonb :metrics, default: {}
      t.datetime :last_failure_at
      t.datetime :last_success_at
      t.datetime :opened_at
      t.datetime :half_opened_at
      t.timestamps

      t.index [ :service, :state ]
      t.index :state
      t.index [ :name, :service ], unique: true
    end

    create_table :circuit_breaker_events, id: :uuid do |t|
      t.references :circuit_breaker, type: :uuid, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :old_state
      t.string :new_state
      t.integer :failure_count
      t.text :error_message
      t.integer :duration_ms
      t.timestamps

      t.index [ :circuit_breaker_id, :created_at ]
      t.index :event_type
    end
  end
end
