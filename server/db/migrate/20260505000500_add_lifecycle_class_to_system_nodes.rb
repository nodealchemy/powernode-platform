# frozen_string_literal: true

# Phase 2.5 hardening — add `lifecycle_class` enum to system_nodes so
# the platform + agent can short-circuit expensive bootstrap for
# instances that won't live long enough to benefit.
#
# Today's design assumes every NodeInstance is long-lived. The
# tmpfs_store flag on Node is binary (true=tmpfs, false=disk-persistent)
# but the use cases form a spectrum:
#
#   persistent — long-lived, image cache + container state survive
#                reboot. Default. Sweet spot for Phase 1 single-host
#                Docker + Phase 2 K3s bootstrap nodes.
#   ephemeral  — short-lived (minutes to hours). Auto-defaults
#                tmpfs_store=true. Agent reconciler skips expensive
#                bootstrap when feasible (e.g. don't request a 90-day
#                TLS cert for a 10-minute job).
#   spot       — operator opts in to provider-side spot/preemptible
#                instances. Treated as ephemeral for storage/bootstrap
#                purposes; reapers prune orphaned bookkeeping rows
#                aggressively.
#
# This migration adds the column with a CHECK enum and defaults all
# existing rows to 'persistent' (no behavior change). Phase 2.5
# follow-on work (DockerHost reaper, agent ephemeral short-circuit)
# reads this column to decide policy.
class AddLifecycleClassToSystemNodes < ActiveRecord::Migration[8.1]
  def up
    add_column :system_nodes, :lifecycle_class, :string,
               null: false, default: "persistent"

    add_check_constraint :system_nodes,
      "lifecycle_class IN ('persistent', 'ephemeral', 'spot')",
      name: "chk_system_nodes_lifecycle_class"

    add_index :system_nodes, :lifecycle_class
  end

  def down
    remove_index :system_nodes, :lifecycle_class
    remove_check_constraint :system_nodes,
      name: "chk_system_nodes_lifecycle_class"
    remove_column :system_nodes, :lifecycle_class
  end
end
