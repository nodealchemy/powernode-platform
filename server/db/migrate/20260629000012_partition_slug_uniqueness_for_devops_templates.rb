# frozen_string_literal: true

# Partition slug uniqueness by scope for ai_devops_templates — the same fix as
# knowledge_base_articles + ai_skills (20260629000011). DevOps templates are
# seeded as GLOBAL content (account_id nil, upserted by source_key = slug), so a
# pre-existing account-scoped row shadowing a global slug could abort db:seed
# under the old single GLOBAL unique slug index. Replace it with two partial
# unique indexes (globals unique among globals, account rows unique within their
# account), matching shared_prompt_templates / roles.
class PartitionSlugUniquenessForDevopsTemplates < ActiveRecord::Migration[8.1]
  TABLE = :ai_devops_templates

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
