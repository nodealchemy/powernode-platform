# frozen_string_literal: true

class AddRequiredRolesToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :required_roles, :text, comment: 'JSON array of role names that are required for users on this plan'

    # Set default required roles for existing plans
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE plans#{' '}
          SET required_roles = '["member"]'
          WHERE required_roles IS NULL
        SQL
      end
    end
  end
end
