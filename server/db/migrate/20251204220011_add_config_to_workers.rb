# frozen_string_literal: true

class AddConfigToWorkers < ActiveRecord::Migration[8.0]
  def change
    add_column :workers, :config, :jsonb, default: {}, null: false
  end
end
