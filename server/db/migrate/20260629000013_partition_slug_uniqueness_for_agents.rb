# frozen_string_literal: true

# Align ai_agents' slug index with its model. Ai::Agent already validates slug
# uniqueness scope: :account_id (globalized in D8), but the DB still carried a
# single GLOBAL unique slug index — a mismatch that rejects an account agent
# overriding a global slug at the DB layer even though the model allows it. Swap
# it for the scope-partitioned partial indexes used by the other GloballyScopable
# models (knowledge_base_articles / ai_skills / ai_devops_templates /
# shared_prompt_templates). Strictly more permissive, so existing data is valid.
class PartitionSlugUniquenessForAgents < ActiveRecord::Migration[8.1]
  TABLE = :ai_agents

  def up
    old_index = "index_#{TABLE}_on_slug"
    remove_index TABLE, name: old_index if index_name_exists?(TABLE, old_index)

    account_index = "index_#{TABLE}_on_account_id_and_slug"
    unless index_name_exists?(TABLE, account_index)
      add_index TABLE, %i[account_id slug], unique: true,
                where: "account_id IS NOT NULL", name: account_index
    end

    global_index = "index_#{TABLE}_on_slug_global"
    unless index_name_exists?(TABLE, global_index)
      add_index TABLE, :slug, unique: true,
                where: "account_id IS NULL", name: global_index
    end
  end

  def down
    %W[index_#{TABLE}_on_slug_global index_#{TABLE}_on_account_id_and_slug].each do |idx|
      remove_index TABLE, name: idx if index_name_exists?(TABLE, idx)
    end
    old_index = "index_#{TABLE}_on_slug"
    add_index TABLE, :slug, unique: true, name: old_index unless index_name_exists?(TABLE, old_index)
  end
end
