# frozen_string_literal: true

class CreateAiExecutionTraces < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_execution_traces, id: :uuid do |t|
      t.string :trace_id, null: false, index: { unique: true }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :trace_type, null: false
      t.string :status, default: "running", null: false
      t.string :root_span_id
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.integer :total_tokens, default: 0
      t.decimal :total_cost, precision: 10, scale: 6, default: 0.0
      t.jsonb :metadata, default: {}
      t.text :error
      t.jsonb :output

      t.timestamps
    end

    add_index :ai_execution_traces, [ :account_id, :started_at ]
    add_index :ai_execution_traces, [ :account_id, :trace_type ]
    add_index :ai_execution_traces, [ :account_id, :status ]
    add_index :ai_execution_traces, :root_span_id

    create_table :ai_execution_trace_spans, id: :uuid do |t|
      t.string :span_id, null: false, index: { unique: true }
      t.references :execution_trace, null: false, foreign_key: { to_table: :ai_execution_traces }, type: :uuid
      t.string :name, null: false
      t.string :span_type, null: false
      t.string :parent_span_id
      t.string :status, default: "running", null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.jsonb :input_data
      t.jsonb :output_data
      t.text :error
      t.jsonb :tokens, default: {}
      t.decimal :cost, precision: 10, scale: 6, default: 0.0
      t.jsonb :events, default: []
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_execution_trace_spans, :parent_span_id
    add_index :ai_execution_trace_spans, [ :execution_trace_id, :started_at ]
    add_index :ai_execution_trace_spans, [ :execution_trace_id, :span_type ]
    add_index :ai_execution_trace_spans, [ :execution_trace_id, :status ]
  end
end
