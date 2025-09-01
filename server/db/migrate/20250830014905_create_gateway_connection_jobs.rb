class CreateGatewayConnectionJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :gateway_connection_jobs, id: :string do |t|
      t.string :gateway, null: false
      t.string :status, null: false, default: 'pending'
      t.json :config_data
      t.json :result
      t.timestamp :completed_at

      t.timestamps
      
      t.index :gateway
      t.index :status
      t.index :created_at
    end
  end
end
