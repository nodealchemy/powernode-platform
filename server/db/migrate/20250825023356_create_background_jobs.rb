class CreateBackgroundJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :background_jobs, id: :string, limit: 36, default: -> { 'gen_random_uuid()::varchar' } do |t|
      t.string :job_id, null: false, limit: 50  # Sidekiq job ID
      t.string :job_type, null: false, limit: 100
      t.string :status, null: false, limit: 20, default: 'pending'
      t.json :parameters
      t.json :result
      t.text :error_message
      t.json :error_details
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps null: false
    end
    
    add_index :background_jobs, :job_id, unique: true
    add_index :background_jobs, :job_type
    add_index :background_jobs, :status
    add_index :background_jobs, [:job_type, :status]
    add_index :background_jobs, :created_at
  end
end
