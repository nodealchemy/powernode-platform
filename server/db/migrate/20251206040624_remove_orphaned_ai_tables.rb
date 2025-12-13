# frozen_string_literal: true

# Removes orphaned database tables that were created for planned features
# but never implemented. These tables have no models, no controller usage,
# and no service references anywhere in the codebase.
#
# Tables being removed:
# - ai_template_installations: Child table of ai_agent_templates (dropped first due to FK)
# - ai_agent_templates: Unimplemented template marketplace feature
# - ai_knowledge_documents: Unimplemented RAG/embedding feature
# - ai_search_indices: Unimplemented search index registry
# - app_analytics: Unimplemented analytics aggregation (raw data in other tables)
class RemoveOrphanedAiTables < ActiveRecord::Migration[8.0]
  def up
    # Drop child tables first due to foreign key constraints
    drop_table :ai_template_installations, if_exists: true
    drop_table :ai_agent_templates, if_exists: true
    drop_table :ai_knowledge_documents, if_exists: true
    drop_table :ai_search_indices, if_exists: true
    drop_table :app_analytics, if_exists: true
  end

  def down
    # These tables were orphaned with no implementation.
    # If needed in the future, they should be recreated with proper
    # models and integration rather than restored to orphaned state.
    raise ActiveRecord::IrreversibleMigration,
          'Orphaned tables cannot be restored. Create new migrations if features are needed.'
  end
end
