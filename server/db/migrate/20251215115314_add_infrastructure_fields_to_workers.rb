# frozen_string_literal: true

class AddInfrastructureFieldsToWorkers < ActiveRecord::Migration[8.0]
  def change
    add_column :workers, :worker_type, :string, null: false, default: 'background'
    add_column :workers, :capabilities, :jsonb, null: false, default: {}

    add_index :workers, :worker_type
    add_index :workers, :capabilities, using: :gin

    add_check_constraint :workers,
      "worker_type IN ('background', 'infrastructure')",
      name: 'workers_worker_type_check'
  end
end
