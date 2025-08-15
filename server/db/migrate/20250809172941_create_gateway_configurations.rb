class CreateGatewayConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :gateway_configurations, id: :string do |t|
      t.string :provider, null: false
      t.string :key_name, null: false
      t.text :encrypted_value, null: false

      t.timestamps
    end

    add_index :gateway_configurations, [:provider, :key_name], unique: true
    add_index :gateway_configurations, :provider
  end
end
