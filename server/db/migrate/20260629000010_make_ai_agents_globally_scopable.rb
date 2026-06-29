# frozen_string_literal: true

# Make Ai::Agent globally scopable — mirrors the Ai::Skill global/account model
# (GloballyScopable). Fundamental core/system agents become GLOBAL (account_id
# nil, seed-managed via source_key); accounts get fully-editable per-account
# overrides/clones (account_id set, cloned_from_id provenance) that resolve in
# preference to the global default.
#
# Behavior-preserving: existing rows keep their account_id; nothing becomes
# global until the agent seeds are migrated to account_id: nil.
class MakeAiAgentsGloballyScopable < ActiveRecord::Migration[8.0]
  def up
    # account_id becomes nullable (nil = global, platform-provided).
    change_column_null :ai_agents, :account_id, true

    # GloballyScopable provenance columns (same shape as ai_skills).
    add_column :ai_agents, :source_key,      :string,  limit: 255 unless column_exists?(:ai_agents, :source_key)
    add_column :ai_agents, :cloned_from_id,  :uuid                unless column_exists?(:ai_agents, :cloned_from_id)
    add_column :ai_agents, :source_version,  :string              unless column_exists?(:ai_agents, :source_version)
    add_column :ai_agents, :source_snapshot, :jsonb, default: {}, null: false unless column_exists?(:ai_agents, :source_snapshot)
    add_column :ai_agents, :is_system,       :boolean, default: false, null: false unless column_exists?(:ai_agents, :is_system)

    add_index :ai_agents, :source_key,     name: "index_ai_agents_on_source_key"     unless index_exists?(:ai_agents, :source_key)
    add_index :ai_agents, :cloned_from_id, name: "index_ai_agents_on_cloned_from_id" unless index_exists?(:ai_agents, :cloned_from_id)
    add_index :ai_agents, :is_system,      name: "index_ai_agents_on_is_system"      unless index_exists?(:ai_agents, :is_system)
  end

  def down
    remove_index :ai_agents, name: "index_ai_agents_on_is_system"      if index_exists?(:ai_agents, :is_system)
    remove_index :ai_agents, name: "index_ai_agents_on_cloned_from_id" if index_exists?(:ai_agents, :cloned_from_id)
    remove_index :ai_agents, name: "index_ai_agents_on_source_key"     if index_exists?(:ai_agents, :source_key)
    remove_column :ai_agents, :is_system       if column_exists?(:ai_agents, :is_system)
    remove_column :ai_agents, :source_snapshot if column_exists?(:ai_agents, :source_snapshot)
    remove_column :ai_agents, :source_version  if column_exists?(:ai_agents, :source_version)
    remove_column :ai_agents, :cloned_from_id  if column_exists?(:ai_agents, :cloned_from_id)
    remove_column :ai_agents, :source_key      if column_exists?(:ai_agents, :source_key)

    # NOTE: account_id is intentionally NOT restored to NOT NULL on down —
    # any global rows created meanwhile would violate it. Re-add the constraint
    # manually only after confirming no global agents exist.
  end
end
