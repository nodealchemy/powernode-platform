# frozen_string_literal: true

class AddPublisherProfileToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :publisher_display_name, :string
    add_column :accounts, :publisher_bio, :text
    add_column :accounts, :publisher_website, :string
    add_column :accounts, :publisher_logo_url, :string
  end
end
