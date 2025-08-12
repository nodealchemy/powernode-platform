class CreateAdminSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_settings, id: :string do |t|
      t.string :key, null: false
      t.text :value

      t.timestamps
    end
    add_index :admin_settings, :key, unique: true
  end
end
