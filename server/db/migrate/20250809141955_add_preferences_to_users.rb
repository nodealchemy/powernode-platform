class AddPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :preferences, :text
    add_column :users, :notification_preferences, :text
  end
end
