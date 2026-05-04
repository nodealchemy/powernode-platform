# frozen_string_literal: true

# Phase 2.5 hardening — sibling fix to FixDockerHostsNodeInstanceCascade.
#
# The original sdwan_peers migration created an FK without an on_delete
# action (PG default = NO ACTION), which means destroying a NodeInstance
# with attached peers crashes with `update or delete on table
# "system_node_instances" violates foreign key constraint
# fk_rails_426e04df1a on table "sdwan_peers"`.
#
# An SDWAN peer membership is meaningless when its NodeInstance is gone.
# Cascade is the correct action — matches the Devops::DockerHost +
# Devops::KubernetesNode pattern (now both cascade after the prior
# migration).
#
# Reproduced via:
#   instance = ...; peer = Sdwan::Peer.create!(node_instance: instance, ...)
#   instance.destroy  # → ForeignKeyViolation
#
# Fix: drop + re-add the FK with on_delete: :cascade.
class FixSdwanPeersNodeInstanceCascade < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :sdwan_peers, :system_node_instances
    add_foreign_key :sdwan_peers, :system_node_instances,
                    column: :node_instance_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :sdwan_peers, :system_node_instances
    add_foreign_key :sdwan_peers, :system_node_instances,
                    column: :node_instance_id
  end
end
