# frozen_string_literal: true

# Component status plane, increment A6 — `Platform::Investigation` (design §5.3).
#
# ONE OPEN INVESTIGATION PER COMPONENT, enforced by the database rather than by
# the service that creates them. `fingerprint` is derived from
# (account, component_kind, component_ref) and the uniqueness is PARTIAL — it
# applies only while `status` is open. That is the `AgentObservation` dedupe
# shape, and the reason for the partial form is the whole point: a component
# that broke, was investigated, and broke again next month must be able to have
# a second investigation. A plain unique index would make the first one
# permanent and the second impossible.
#
# The trigger cap (`platform.investigation.daily_cap`) is deliberately NOT a
# constraint here. A cap is a policy an operator changes; a constraint is a
# shape the data has. Encoding a policy as a constraint means the day somebody
# raises the cap, the rows they are allowed to create are rejected by the
# database with an error that names none of that.
class CreatePlatformInvestigations < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_investigations, id: :uuid, default: -> { "uuidv7()" } do |t|
      # Nullable for the same reason the status row's is: a process-wide
      # component has no tenant, so an investigation of one has none either.
      # `index: false`: the two indexes below are both account_id-LEADING, so a
      # bare index on the column alone is redundant with them and buys only
      # write cost. (The same redundancy was just removed from
      # platform_status_events by 20260910250000; adding it back here would
      # re-file the debt one table over.)
      t.references :account, type: :uuid, foreign_key: { on_delete: :cascade },
                   null: true, index: false

      t.string :component_kind, null: false
      t.string :component_ref, null: false

      # operator | stuck | down — validated on the model, where the list can
      # carry its reasoning.
      t.string :trigger, null: false
      t.string :status, null: false, default: "open"

      # Derived, never hand-written. See the class comment.
      t.string :fingerprint, null: false

      t.jsonb :evidence, null: false, default: {}
      t.jsonb :hypotheses, null: false, default: []
      t.text :conclusion

      # The canonical agent that ranked the hypotheses, when one did. Nullable:
      # an investigation whose evidence assembly found nothing never reaches an
      # agent, and inventing an attribution for it would be a lie about who
      # concluded what.
      t.references :agent, type: :uuid, foreign_key: { to_table: :ai_agents, on_delete: :nullify }, null: true

      t.decimal :cost_usd, precision: 12, scale: 6
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    # The open-fingerprint rule. NULLS NOT DISTINCT so a shared (null-account)
    # component gets the same one-open-at-a-time guarantee an account-scoped one
    # does — without it, every sweep of every account could open another
    # investigation of the same shared component.
    add_index :platform_investigations, %i[account_id fingerprint],
              unique: true, nulls_not_distinct: true,
              where: "status = 'open'",
              name: "index_platform_investigations_open_fingerprint"

    add_index :platform_investigations, %i[account_id created_at],
              name: "index_platform_investigations_on_account_and_created_at"

    add_index :platform_investigations, %i[component_kind component_ref],
              name: "index_platform_investigations_on_component"
  end
end
