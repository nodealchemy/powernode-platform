# frozen_string_literal: true

# Workers-as-NodeInstances bridge (Stage 8b.1).
#
# A Sidekiq Worker is now backed by a NodeInstance — the NodeInstance
# carries the mTLS identity (cert at /persist/var/lib/powernode/pki/,
# rotation via the agent's CertRotator), and the Worker row carries the
# domain-specific configuration (permissions, queue assignments,
# worker_type). The cert's CN is the NodeInstance.id; InternalBaseController
# looks up the Worker via `Worker.find_by(node_instance_id: subject_cn)`.
#
# Column is nullable + no FK constraint at the DB layer — the FK target
# (`system_node_instances`) lives in the system extension, and core can't
# depend on extension tables. The `belongs_to :node_instance` association
# is added via a system extension decorator. CI workers (per Stage 3)
# remain non-NodeInstance-backed (column NULL) since they auth via Bearer,
# not mTLS.
class AddNodeInstanceIdToWorkers < ActiveRecord::Migration[8.0]
  def change
    add_column :workers, :node_instance_id, :uuid, null: true
    add_index  :workers, :node_instance_id, unique: true, where: "node_instance_id IS NOT NULL"
  end
end
