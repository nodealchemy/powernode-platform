# frozen_string_literal: true

class CreateDevopsPortAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :devops_port_allocations, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.integer :port, null: false
      t.string :protocol, default: "tcp", null: false
      t.string :host_identifier, null: false
      t.string :allocatable_type, null: false
      t.uuid :allocatable_id, null: false
      t.string :purpose
      t.string :status, default: "active", null: false
      t.datetime :released_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :devops_port_allocations, [:host_identifier, :port, :protocol],
              unique: true, where: "status = 'active'",
              name: "idx_port_allocations_unique_active"
    add_index :devops_port_allocations, [:allocatable_type, :allocatable_id],
              name: "idx_port_allocations_allocatable"
    add_index :devops_port_allocations, :status
  end
end
