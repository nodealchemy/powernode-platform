# frozen_string_literal: true

# Environment campaign, increment 3 — a gated operation records the
# environment it was evaluated against, so the audit trail, the approval
# inbox and later blast-radius accounting can group by plane. Nullable: an
# operation whose subject has no resolvable environment (or predates this
# column) carries none, and the gate applies no overlay to it.
#
# ON DELETE SET NULL: deferred operations are a permanent audit trail and must
# outlive an environment an operator removes; the slug is preserved in the
# approval request's request_data, so nothing is lost but the join.
class AddEnvironmentToAiDeferredOperations < ActiveRecord::Migration[8.0]
  def up
    add_reference :ai_deferred_operations, :environment, type: :uuid,
                  foreign_key: { to_table: :ai_environments, on_delete: :nullify }
  end

  # Explicit: `remove_reference` matches the foreign key by the SAME option hash
  # it was added with, and `on_delete` is not part of that match — passing it
  # makes the lookup fail with "has no foreign key for ai_environments".
  def down
    remove_reference :ai_deferred_operations, :environment, type: :uuid,
                     foreign_key: { to_table: :ai_environments }
  end
end
