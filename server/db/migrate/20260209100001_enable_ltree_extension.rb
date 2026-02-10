# frozen_string_literal: true

class EnableLtreeExtension < ActiveRecord::Migration[8.0]
  def change
    enable_extension "ltree"
  end
end
