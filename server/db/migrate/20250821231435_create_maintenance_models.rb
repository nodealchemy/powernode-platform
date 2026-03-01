# frozen_string_literal: true

class CreateMaintenanceModels < ActiveRecord::Migration[8.0]
  def change
    # Database Backups table
    create_table :database_backups, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :filename, null: false
      t.string :backup_type, null: false # full, incremental, schema_only
      t.string :status, null: false, default: 'pending' # pending, in_progress, completed, failed
      t.text :description
      t.text :file_path
      t.bigint :file_size
      t.integer :duration_seconds
      t.text :error_message
      t.timestamp :started_at
      t.timestamp :completed_at
      t.string :user_id, limit: 36, null: false
      t.timestamps null: false

      t.index :status
      t.index :backup_type
      t.index :created_at
      t.index :user_id
    end

    # Database Restores table
    create_table :database_restores, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :database_backup_id, limit: 36, null: false
      t.string :status, null: false, default: 'pending' # pending, in_progress, completed, failed
      t.integer :duration_seconds
      t.text :error_message
      t.timestamp :started_at
      t.timestamp :completed_at
      t.string :user_id, limit: 36, null: false
      t.timestamps null: false

      t.index :database_backup_id
      t.index :status
      t.index :created_at
      t.index :user_id
    end

    # Scheduled Tasks table
    create_table :scheduled_tasks, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :name, null: false
      t.string :description
      t.string :task_type, null: false # database_backup, data_cleanup, system_health_check, etc.
      t.string :cron_schedule, null: false
      t.boolean :enabled, default: true
      t.text :command # For custom command tasks
      t.json :parameters # Additional task parameters
      t.string :user_id, limit: 36, null: false
      t.timestamps null: false

      t.index :enabled
      t.index :task_type
      t.index :user_id
      t.index :name, unique: true
    end

    # Task Executions table
    create_table :task_executions, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :scheduled_task_id, limit: 36, null: false
      t.string :status, null: false, default: 'pending' # pending, running, completed, failed
      t.string :triggered_by, null: false, default: 'scheduled' # scheduled, manual
      t.text :output
      t.text :error_message
      t.timestamp :started_at
      t.timestamp :completed_at
      t.string :user_id, limit: 36 # null for scheduled executions
      t.timestamps null: false

      t.index :scheduled_task_id
      t.index :status
      t.index :triggered_by
      t.index :created_at
      t.index :user_id
    end

    # System Health Checks table
    create_table :system_health_checks, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :check_type, null: false # basic, detailed, comprehensive
      t.string :overall_status, null: false # healthy, warning, critical
      t.json :health_data, null: false
      t.integer :response_time_ms
      t.timestamp :checked_at, null: false
      t.timestamps null: false

      t.index :check_type
      t.index :overall_status
      t.index :checked_at
    end

    # System Operations Log table
    create_table :system_operations, id: false do |t|
      t.string :id, limit: 36, primary_key: true, default: -> { 'gen_random_uuid()' }
      t.string :operation_type, null: false # restart_service, database_optimize, etc.
      t.string :status, null: false # pending, in_progress, completed, failed
      t.json :parameters
      t.json :result
      t.text :error_message
      t.timestamp :started_at
      t.timestamp :completed_at
      t.string :user_id, limit: 36, null: false
      t.timestamps null: false

      t.index :operation_type
      t.index :status
      t.index :started_at
      t.index :user_id
    end

    # Add foreign key constraints
    add_foreign_key :database_backups, :users, column: :user_id
    add_foreign_key :database_restores, :database_backups, column: :database_backup_id
    add_foreign_key :database_restores, :users, column: :user_id
    add_foreign_key :scheduled_tasks, :users, column: :user_id
    add_foreign_key :task_executions, :scheduled_tasks, column: :scheduled_task_id
    add_foreign_key :task_executions, :users, column: :user_id
    add_foreign_key :system_operations, :users, column: :user_id
  end
end
