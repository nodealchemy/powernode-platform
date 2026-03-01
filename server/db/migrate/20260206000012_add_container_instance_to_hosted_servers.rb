# frozen_string_literal: true

class AddContainerInstanceToHostedServers < ActiveRecord::Migration[8.0]
  def change
    add_reference :mcp_hosted_servers, :container_instance,
                  type: :uuid,
                  foreign_key: { to_table: :devops_container_instances },
                  null: true,
                  index: true
  end
end
