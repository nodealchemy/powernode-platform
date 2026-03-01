# frozen_string_literal: true

class AddPriorityToNotifications < ActiveRecord::Migration[8.0]
  def change
    add_column :notifications, :priority, :integer, default: 0
    add_index :notifications, :priority
  end
end
