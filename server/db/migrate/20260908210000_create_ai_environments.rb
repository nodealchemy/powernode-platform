# frozen_string_literal: true

# Environment campaign, increment 1 — the platform gets a noun for "which
# plane is this".
#
# Until now nothing in the schema distinguished the control plane from a
# throwaway CI builder: every sensor, verb and agent saw one undifferentiated
# fleet, so the fleet tick treated the self-hosting node like any other node
# and no verb could answer "what is running in prod". Autonomy posture, blast
# radius and promotion gates all need SOMETHING to vary on; this is it.
#
# CORE, NOT EXTENSION. The rows that carry an environment (templates, nodes,
# instances, pools, peers) are owned by the system extension, but the noun
# itself is generic — projects, policies and the autonomy gate are core and
# must read it without naming an extension. The extension references this
# table from its own band (cross-owner FKs live in the later-band owner).
#
# The defaults (dev, ci, staging, ops, prod) are seeded PER ACCOUNT by
# Ai::Environment.ensure_defaults_for!, both at account creation and, for the
# installed base, by the data migration that follows this one — seeds never
# re-run after first boot, so a seed alone would leave every existing account
# without one.
class CreateAiEnvironments < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_environments, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: false, type: :uuid, foreign_key: false

      t.string  :slug, null: false               # dev | ci | staging | ops | prod (extensible)
      t.string  :name, null: false
      t.text    :description
      # Ordering rung on the promotion ladder: a version moves to a higher tier
      # only through a gate. 0 = lowest.
      t.integer :tier, null: false, default: 0
      # supervised | monitored | trusted | autonomous — what an infrastructure
      # agent may decide here without an operator (read by the gate, incr. 3).
      t.string  :default_decision_authority, null: false, default: "trusted"
      # Action categories that ALWAYS require approval in this environment,
      # regardless of agent trust. Increment 3 wires the gate to it.
      t.jsonb   :approval_required_categories, null: false, default: []
      # Upper bound on the number of nodes one rollout/decision may touch here.
      # NULL = no environment-level bound.
      t.integer :max_blast_radius
      # A protected environment refuses every destructive category without a
      # person, and sensors never auto-remediate against it (the control plane
      # and prod).
      t.boolean :is_protected, null: false, default: false
      # The environment a new template lands in when its creator says nothing.
      t.boolean :is_default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.jsonb   :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ai_environments, %i[account_id slug], unique: true, name: "index_ai_environments_on_account_and_slug"
    add_index :ai_environments, %i[account_id tier]
    # At most ONE default per account.
    add_index :ai_environments, :account_id, unique: true, where: "is_default",
              name: "index_ai_environments_one_default_per_account"

    # A project runs IN an environment. Nullable: every project that exists
    # today has none, and the front door (later campaign) is what asks.
    add_reference :ai_projects, :environment, type: :uuid, foreign_key: { to_table: :ai_environments }
  end
end
