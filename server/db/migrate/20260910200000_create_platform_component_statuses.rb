# frozen_string_literal: true

# Component status plane, increment A1 — the platform gets ONE table that says
# what every component is doing right now.
#
# Before this, "is the platform healthy" had no single answer: each subsystem
# carried its own status enum, the composite probe computed a verdict it threw
# away, and the operator screen re-derived a different story per panel. This
# table is the one place a sweep writes a verdict, and the one place a rollup,
# an impact walk or an escalation reads one.
#
# CORE, NOT EXTENSION. The components themselves (nodes, instances, peers,
# certificates) are owned by extensions; the NOUN "a component has a status"
# is generic. Contributors register into Platform::Status::Registry from
# wherever they live and core never names them.
#
# NULL account_id is legitimate, not a defect: a process-wide kind
# (`account_scoped? == false`) has no tenant. Postgres treats NULLs as
# distinct in a unique index by default, which would let the same shared
# component be inserted twice, so the unique index is declared
# NULLS NOT DISTINCT (Postgres 15+; this deployment runs 16.2). One row per
# (account, kind, ref) — with a null account counting as one value.
class CreatePlatformComponentStatuses < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_component_statuses, id: :uuid, default: -> { "uuidv7()" } do |t|
      # Nullable: shared/process-wide kinds carry no tenant (design §4.4).
      t.references :account, null: true, type: :uuid, foreign_key: false
      # Which plane this component sits in. Most core kinds carry none, and
      # the environment filter is three-valued because of that (design §4.6).
      t.references :environment, null: true, type: :uuid,
                                 foreign_key: { to_table: :ai_environments, on_delete: :nullify }

      # Registry key and the contributor's stable id for the record.
      t.string :component_kind, null: false
      t.string :component_ref,  null: false
      t.string :display_name

      # ok | held | progressing | not_measured | degraded | down (design §4.1).
      t.string :verdict, null: false, default: "not_measured"

      # The generation/version the observation was made against, when the
      # source has one. A string because sources spell it differently
      # (integer counters, shas, module version ids).
      t.string :observed_generation

      # JSON columns carry NO database default on purpose: the model owns the
      # default as a lambda (convention), which keeps one source of truth.
      t.jsonb :presentation      # {icon:, label:, group_order:}
      t.jsonb :links             # [{label:, path:}]
      t.jsonb :actions           # [{key:, label:, method:, path:, permission:, ...}]
      t.jsonb :conditions        # [design §4.2]
      t.jsonb :dependencies      # [{kind:, ref:, relation:}]
      t.jsonb :remediation       # {state:, signal_kind:, fingerprint:, ...}

      t.datetime :observed_at
      t.datetime :last_seen_sweep_at
      t.datetime :last_notified_at

      t.timestamps
    end

    # One row per component. NULLS NOT DISTINCT so the shared (null-account)
    # kinds cannot duplicate — the whole point of allowing a null account.
    add_index :platform_component_statuses, %i[account_id component_kind component_ref],
              unique: true, nulls_not_distinct: true,
              name: "index_platform_component_statuses_on_account_kind_ref"

    # The rollup's read path.
    add_index :platform_component_statuses, %i[account_id verdict],
              name: "index_platform_component_statuses_on_account_and_verdict"

    # NOTE (A1 review L1): this index was justified by a comment claiming "the
    # reap arm scans by kind + freshness". It does not — the reap predicate is
    # account + freshness. The index is dropped by
    # 20260910220000_tighten_platform_status_tables. It is left here rather
    # than edited away because this migration has already run everywhere;
    # editing an applied migration is how a schema and its schema_migrations
    # row stop agreeing.
    add_index :platform_component_statuses, %i[component_kind last_seen_sweep_at],
              name: "index_platform_component_statuses_on_kind_and_last_seen"
  end
end
