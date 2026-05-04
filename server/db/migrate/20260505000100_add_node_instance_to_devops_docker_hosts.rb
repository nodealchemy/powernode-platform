# frozen_string_literal: true

# Phase B docker-runtime — wire `Devops::DockerHost` to its backing
# `System::NodeInstance` so the platform can auto-register a daemon
# when an instance comes up with the `docker-engine` NodeModule
# assigned. Existing operator-registered hosts remain valid via the
# `provisioning_state: 'external'` enum default; new
# auto-provisioned hosts use `'managed'` and cascade-delete on
# NodeInstance terminate.
class AddNodeInstanceToDevopsDockerHosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :devops_docker_hosts,
                  :node_instance,
                  type: :uuid,
                  foreign_key: { to_table: :system_node_instances, on_delete: :nullify },
                  null: true,
                  index: { unique: true,
                           where: "node_instance_id IS NOT NULL",
                           name: "idx_devops_docker_hosts_node_instance_unique" }

    # external = operator-registered (legacy / out-of-band managed)
    # managed  = NodeInstance-backed; agent installed dockerd; lifecycle
    #            tied to the instance
    add_column :devops_docker_hosts,
               :provisioning_state,
               :string,
               null: false,
               default: "external"

    add_check_constraint :devops_docker_hosts,
                         "provisioning_state IN ('external', 'managed')",
                         name: "devops_docker_hosts_provisioning_state_enum"

    # `managed` rows MUST have a node_instance_id; `external` rows MUST NOT.
    # Keeps the data model honest — no orphaned managed hosts.
    add_check_constraint :devops_docker_hosts,
                         "(provisioning_state = 'external' AND node_instance_id IS NULL) OR " \
                         "(provisioning_state = 'managed'  AND node_instance_id IS NOT NULL)",
                         name: "devops_docker_hosts_provisioning_state_consistency"
  end
end
