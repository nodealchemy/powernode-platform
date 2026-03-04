# frozen_string_literal: true

class AddSourceToDevopsSwarmStacks < ActiveRecord::Migration[8.0]
  def change
    add_column :devops_swarm_stacks, :source, :string, null: false, default: "platform"
  end
end
