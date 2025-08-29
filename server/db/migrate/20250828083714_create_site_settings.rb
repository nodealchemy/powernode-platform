class CreateSiteSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :site_settings, id: :string do |t|
      t.string :key, null: false
      t.text :value
      t.text :description
      t.string :setting_type, null: false
      t.boolean :is_public, default: false

      t.timestamps
    end
    
    add_index :site_settings, :key, unique: true
    add_index :site_settings, :setting_type
    add_index :site_settings, :is_public
  end
end
