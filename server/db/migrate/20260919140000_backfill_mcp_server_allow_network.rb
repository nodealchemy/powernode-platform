# frozen_string_literal: true

# IMP-a50680fd53d8 (MCP isolation Phase 1 T2). The worker's stdio spawn
# path is being wrapped in a systemd-run sandbox with IPAddressDeny=any
# by default; capabilities["allow_network"] (admin-gated, same trust
# tier and gating as allow_extended_commands, carried to the worker by
# the same IMP-427e98cae0be capabilities serialization allowlist) opts a
# specific stdio MCP server OUT of that network deny.
#
# Every EXISTING stdio server was configured, and presumably runs, with
# NO network restriction at all — the sandbox itself is new. Defaulting
# them to allow_network=false at deploy would silently break every
# already-working server that talks to the network (github, fetch, ...)
# the moment the worker starts enforcing it. Backfill every existing
# stdio server to allow_network=true so nothing breaks on deploy; a NEW
# server created after this migration gets the model's own default
# (false, unaffected by this migration) and an admin opts it into
# network access deliberately.
class BackfillMcpServerAllowNetwork < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE mcp_servers
         SET capabilities = COALESCE(capabilities, '{}'::jsonb) || '{"allow_network": true}'::jsonb,
             updated_at = NOW()
       WHERE connection_type = 'stdio'
         AND NOT (COALESCE(capabilities, '{}'::jsonb) ? 'allow_network')
    SQL
  end

  # A backfilled row cannot be told apart from one an admin later set
  # allow_network=true on explicitly.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
