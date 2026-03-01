# frozen_string_literal: true

class BridgeMcpHostingWithDevopsContainers < ActiveRecord::Migration[8.0]
  def change
    add_reference :mcp_hosted_servers, :container_template,
                  type: :uuid,
                  foreign_key: { to_table: :devops_container_templates },
                  null: true,
                  index: true
  end
end
