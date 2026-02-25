# frozen_string_literal: true

class AddIsSystemToWorkers < ActiveRecord::Migration[8.1]
  def change
    add_column :workers, :is_system, :boolean, default: false, null: false

    # Database-level enforcement: only one system worker can exist
    add_index :workers, :is_system, unique: true, where: "is_system = true",
              name: "index_workers_on_is_system_unique"

    # Backfill: mark existing system workers (those with system_worker role)
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE workers
          SET is_system = true
          WHERE id IN (
            SELECT w.id FROM workers w
            INNER JOIN worker_roles wr ON wr.worker_id = w.id
            INNER JOIN roles r ON r.id = wr.role_id
            WHERE r.name = 'system_worker'
            LIMIT 1
          )
        SQL
      end
    end
  end
end
