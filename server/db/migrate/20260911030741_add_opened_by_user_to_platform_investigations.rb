# frozen_string_literal: true

# Component status plane, A6 re-verification G1(a) — WHO OPENED an investigation.
#
# Ranking an investigation spends money through `Ai::McpAgentExecutor`, and that
# executor's security gate reads the execution's `user_id` as "a human initiated
# this, so approval is implicit". Ranking used to fill that user with the agent's
# creator or the account's first user, which forged a person's consent onto every
# AUTOMATIC investigation and waived the capability-matrix gate that refuses the
# identical call without it.
#
# The only honest source for that user is the person who pressed Investigate, and
# this column records them. The two doors a person acts through (the REST button
# and the MCP verb) set it; the status emitter never does. An automatic
# investigation therefore carries NULL, and its ranking reaches the gate as what
# it is: machine-initiated spend, which needs an agent-scoped grant (A6b).
#
# `on_delete: :nullify`: deleting a user must neither delete the record of what
# was investigated nor leave a dangling id. Indexed because the nullify on a user
# delete looks rows up by this column.
class AddOpenedByUserToPlatformInvestigations < ActiveRecord::Migration[8.0]
  def change
    add_reference :platform_investigations, :opened_by_user, type: :uuid, null: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
