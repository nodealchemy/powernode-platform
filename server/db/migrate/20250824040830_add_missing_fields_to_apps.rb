class AddMissingFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :icon, :string
    add_column :apps, :tags, :jsonb, default: []
    add_column :apps, :homepage_url, :string
    add_column :apps, :documentation_url, :string
    add_column :apps, :support_url, :string
    add_column :apps, :repository_url, :string
    add_column :apps, :license, :string
    add_column :apps, :privacy_policy_url, :string
    add_column :apps, :terms_of_service_url, :string
  end
end
