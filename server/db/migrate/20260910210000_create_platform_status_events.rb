# frozen_string_literal: true

# Component status plane, increment A2 — the durable record of a transition.
#
# A1 made the sweep report transitions; it deliberately wrote none, so this
# increment can be THE producer. Every verdict change lands here exactly once,
# and every consumer (the operator feed, escalation in A7, the extension's
# fleet feed mirror) reads this table or the broadcast that accompanies it.
# Nothing else writes a status event.
#
# WHY A SEPARATE TABLE AND NOT A COLUMN ON THE STATUS ROW. The status row is a
# CURRENT-STATE row, upserted in place: it can answer "what is it doing now"
# and nothing else. "How often has this flapped today", "what broke first"
# and "did anyone get told" are questions about HISTORY, and a row that is
# overwritten sixty times a minute cannot answer any of them.
#
# account_id is nullable for the same reason it is on the status row: a
# process-wide component has no tenant. component_status_id nullifies rather
# than cascades — when the reap arm deletes a component whose record is gone,
# the HISTORY of what it did must survive it. component_kind and component_ref
# are duplicated onto the event for exactly that case: after the status row is
# gone, the event still says what it was about.
class CreatePlatformStatusEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_status_events, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: true, type: :uuid, foreign_key: false
      t.references :component_status, null: true, type: :uuid,
                                      foreign_key: { to_table: :platform_component_statuses,
                                                     on_delete: :nullify }

      # Denormalized on purpose: survives the reap of the component it is about.
      t.string :component_kind, null: false
      t.string :component_ref,  null: false

      # platform.component_status_changed | platform.component_down
      t.string :kind, null: false

      # Nullable `from_verdict`: a component's FIRST sighting is a transition
      # from nothing, and writing "ok" or "not_measured" there would invent a
      # history the platform never observed.
      t.string :from_verdict
      t.string :to_verdict, null: false

      # No database default — the model owns it as a lambda (convention).
      t.jsonb :payload

      t.datetime :occurred_at, null: false

      t.timestamps
    end

    # The feed's read: one account's events, newest first.
    add_index :platform_status_events, %i[account_id occurred_at],
              name: "index_platform_status_events_on_account_and_occurred_at"

    # One component's history, newest first — the flap and root-cause reads.
    add_index :platform_status_events, %i[component_kind component_ref occurred_at],
              name: "index_platform_status_events_on_component_and_occurred_at"
  end
end
