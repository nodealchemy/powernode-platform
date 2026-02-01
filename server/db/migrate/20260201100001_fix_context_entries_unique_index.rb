# frozen_string_literal: true

class FixContextEntriesUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    # Remove the old unique index that doesn't account for archived entries
    remove_index :ai_context_entries, name: "idx_entries_context_key"

    # Add partial unique index that only applies to non-archived entries
    add_index :ai_context_entries,
              [:ai_persistent_context_id, :entry_key],
              unique: true,
              where: "archived_at IS NULL",
              name: "idx_entries_context_key_active"
  end
end
