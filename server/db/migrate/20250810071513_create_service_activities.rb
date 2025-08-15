class CreateServiceActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :service_activities, id: :string do |t|
      t.references :service, null: false, foreign_key: true, type: :string
      t.string :action, limit: 100
      t.json :details
      t.datetime :performed_at
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end
    
    # Add indexes for common queries
    add_index :service_activities, [:service_id, :performed_at]
    add_index :service_activities, :action
    add_index :service_activities, :performed_at
  end
end
