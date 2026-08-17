# frozen_string_literal: true

# Remap the retired ai.workflows.* / ai.workflow_executions.* permission grants
# onto the namespaces that replaced them.
#
# "Workflows" was removed as a feature, but its permission namespace outlived it
# and became the de-facto gate for six unrelated subsystems (Ralph loops,
# worktree sessions, Gitea Actions CI, runner dispatch, project init, pipeline
# templates). The catalog now splits them by owning subsystem.
#
# Role.sync_permissions! already prunes grants whose permission left the catalog,
# so the CODE-DEFINED roles heal themselves on the next Role.sync_from_config!.
# This migration exists for the case that sync does NOT cover, called out in
# Role.sync_from_config! itself: "account-scoped roles are created at runtime via
# the API and are never seeded here." Those rows would simply stop matching a
# catalog entry and the role would silently lose the access — the failure mode is
# invisible, because nothing errors; a user just starts getting 403s.
#
# Idempotent: inserts are guarded by NOT EXISTS, and the delete only removes
# names that are no longer in the catalog.
class RemapAiWorkflowsPermissions < ActiveRecord::Migration[8.0]
  # old permission => replacement(s). One old name can fan out to several new
  # ones because a single grant used to cover several subsystems at once.
  MAPPING = {
    "ai.workflows.read" => %w[ai.loops.read ai.worktrees.read devops.ci.read],
    "ai.workflows.create" => %w[ai.loops.create ai.worktrees.create],
    "ai.workflows.update" => %w[ai.loops.update],
    "ai.workflows.delete" => %w[ai.loops.delete],
    "ai.workflows.execute" => %w[ai.loops.execute ai.worktrees.execute devops.ci.write],
    "ai.workflows.manage" => %w[devops.pipelines.write],
    # Retired with no replacement — the features behind them are gone and no
    # code referenced them.
    "ai.workflows.clone" => [],
    "ai.workflows.import" => [],
    "ai.workflows.export" => [],
    "ai.workflow_executions.read" => [],
    "ai.workflow_executions.cancel" => [],
    "ai.workflow_executions.retry" => [],
    "ai.workflow_executions.update" => []
  }.freeze

  def up
    MAPPING.each do |old_name, new_names|
      new_names.each do |new_name|
        # role_permissions is id: false with no created_at/updated_at — it
        # carries granted_at, which has a CURRENT_TIMESTAMP default, so the
        # insert lists only the two real columns. The (role_id,
        # permission_name) unique index backs the NOT EXISTS guard.
        execute(<<~SQL.squish)
          INSERT INTO role_permissions (role_id, permission_name)
          SELECT rp.role_id, #{connection.quote(new_name)}
          FROM role_permissions rp
          WHERE rp.permission_name = #{connection.quote(old_name)}
            AND NOT EXISTS (
              SELECT 1 FROM role_permissions existing
              WHERE existing.role_id = rp.role_id
                AND existing.permission_name = #{connection.quote(new_name)}
            )
        SQL
      end
    end

    execute(<<~SQL.squish)
      DELETE FROM role_permissions
      WHERE permission_name IN (#{MAPPING.keys.map { |n| connection.quote(n) }.join(', ')})
    SQL
  end

  # Deliberately irreversible. Rolling back would have to re-create grants for
  # permissions that no longer exist in the catalog, and it could not tell which
  # of the new grants were pre-existing versus created here — so a "restore"
  # would over- or under-grant. Re-running the catalog sync is the correct
  # recovery path, not a down migration.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
