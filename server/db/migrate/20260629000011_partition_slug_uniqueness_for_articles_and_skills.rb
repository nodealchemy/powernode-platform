# frozen_string_literal: true

# Partition slug uniqueness by scope for GloballyScopable content (knowledge_base
# articles + ai_skills), mirroring shared_prompt_templates / roles / ai_knowledge_bases.
#
# The single GLOBAL unique index on slug is incompatible with the global/account
# override model: an account cannot hold a row that shares (overrides) a global
# slug, and a pre-existing account-scoped row shadowing a global slug aborted
# db:seed (RecordInvalid) when the global content seed ran. Replace it with two
# partial unique indexes: globals unique among globals, account rows unique
# within their own account. Strictly more permissive, so existing data is valid.
class PartitionSlugUniquenessForArticlesAndSkills < ActiveRecord::Migration[8.1]
  TABLES = %i[knowledge_base_articles ai_skills].freeze

  def up
    TABLES.each do |table|
      old_index = "index_#{table}_on_slug"
      remove_index table, name: old_index if index_name_exists?(table, old_index)

      account_index = "index_#{table}_on_account_id_and_slug"
      unless index_name_exists?(table, account_index)
        add_index table, %i[account_id slug], unique: true,
                  where: "account_id IS NOT NULL", name: account_index
      end

      global_index = "index_#{table}_on_slug_global"
      unless index_name_exists?(table, global_index)
        add_index table, :slug, unique: true,
                  where: "account_id IS NULL", name: global_index
      end
    end
  end

  def down
    TABLES.each do |table|
      %W[index_#{table}_on_slug_global index_#{table}_on_account_id_and_slug].each do |idx|
        remove_index table, name: idx if index_name_exists?(table, idx)
      end
      old_index = "index_#{table}_on_slug"
      add_index table, :slug, unique: true, name: old_index unless index_name_exists?(table, old_index)
    end
  end
end
