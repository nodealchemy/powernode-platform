class AddShortDescriptionToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :short_description, :text
  end
end
