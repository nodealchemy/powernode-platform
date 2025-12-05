# frozen_string_literal: true

class AddIsDefaultToFileStorages < ActiveRecord::Migration[8.0]
  def change
    add_column :file_storages, :is_default, :boolean
  end
end
