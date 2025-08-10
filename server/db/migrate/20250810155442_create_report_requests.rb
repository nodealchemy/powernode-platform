class CreateReportRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :report_requests, id: :string do |t|
      t.references :account, null: false, foreign_key: true, type: :string
      t.references :user, null: false, foreign_key: true, type: :string
      t.string :name, null: false
      t.string :report_type, null: false
      t.string :format, null: false
      t.string :status, default: 'pending', null: false
      t.jsonb :parameters
      t.string :file_url
      t.string :file_path
      t.integer :file_size
      t.string :content_type
      t.text :error_message
      t.timestamp :completed_at
      t.timestamps
    end

    add_index :report_requests, :account_id unless index_exists?(:report_requests, :account_id)
    add_index :report_requests, :user_id unless index_exists?(:report_requests, :user_id)
    add_index :report_requests, :status unless index_exists?(:report_requests, :status)
    add_index :report_requests, :created_at unless index_exists?(:report_requests, :created_at)
    add_index :report_requests, :report_type unless index_exists?(:report_requests, :report_type)
    add_index :report_requests, [:account_id, :status] unless index_exists?(:report_requests, [:account_id, :status])
  end
end
