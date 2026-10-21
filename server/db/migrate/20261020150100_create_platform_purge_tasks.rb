# frozen_string_literal: true

# Durable retry record for external cleanup that must follow a committed deletion
# (e.g. purging an account's Vault KV entries). The deletion cannot be rolled back,
# so a failed purge is recorded here and retried by the worker sweep through the
# internal API. subject_id carries no foreign key: it names a row that is gone.
class CreatePlatformPurgeTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_purge_tasks, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :kind, null: false
      t.uuid :subject_id, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 1
      t.string :last_error_class
      t.datetime :next_attempt_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :platform_purge_tasks, %i[status next_attempt_at]
    add_index :platform_purge_tasks, %i[kind subject_id], unique: true, where: "status = 'pending'",
                                                          name: "index_platform_purge_tasks_one_pending_per_subject"
  end
end
