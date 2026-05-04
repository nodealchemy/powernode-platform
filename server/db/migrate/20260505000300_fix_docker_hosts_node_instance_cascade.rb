# frozen_string_literal: true

# Phase 2.5 hardening — fix the latent FK cascade bug discovered during the
# audit on 2026-05-04.
#
# The original migration (20260505000100) declared:
#   foreign_key: { to_table: :system_node_instances, on_delete: :nullify }
#
# Combined with the CHECK constraint
# `devops_docker_hosts_provisioning_state_consistency` which enforces
# "managed rows MUST have node_instance_id IS NOT NULL", terminating a
# NodeInstance with a managed DockerHost would attempt to UPDATE
# node_instance_id=NULL → CHECK fires → destroy fails.
#
# Reproduced via:
#   acct, node, instance = ...
#   host = DockerDaemonProvisionerService.provision!(node_instance: instance, ...)
#   instance.destroy  # → CheckViolation: devops_docker_hosts_provisioning_state_consistency
#
# Fix: change FK action from `nullify` to `cascade`. Matches the
# Devops::KubernetesNode pattern (already cascade) and aligns with the
# Phase 1 plan's "NodeInstance.terminate cascade-deletes the host row"
# decision.
#
# Bonus reaper: clean up any rows that slipped through via direct DB
# writes (provisioning_state='managed' AND node_instance_id IS NULL is
# an impossible state per the CHECK, but we sanity-purge anyway).
class FixDockerHostsNodeInstanceCascade < ActiveRecord::Migration[8.1]
  def up
    # Sanity reaper — should be empty given CHECK, but free safety net.
    impossible = execute(
      "SELECT COUNT(*) FROM devops_docker_hosts " \
      "WHERE provisioning_state = 'managed' AND node_instance_id IS NULL"
    ).first["count"].to_i
    if impossible > 0
      say "  reaping #{impossible} impossible-state managed host row(s)"
      execute(
        "DELETE FROM devops_docker_hosts " \
        "WHERE provisioning_state = 'managed' AND node_instance_id IS NULL"
      )
    end

    # Drop + re-add FK with cascade. Postgres has no ALTER FOREIGN KEY;
    # we drop by index name and re-add with the new on_delete action.
    remove_foreign_key :devops_docker_hosts, :system_node_instances
    add_foreign_key :devops_docker_hosts, :system_node_instances,
                    column: :node_instance_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :devops_docker_hosts, :system_node_instances
    add_foreign_key :devops_docker_hosts, :system_node_instances,
                    column: :node_instance_id, on_delete: :nullify
  end
end
