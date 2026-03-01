# frozen_string_literal: true

class AddConversationManagementFields < ActiveRecord::Migration[8.1]
  def change
    # Conversation management: pins and tags
    add_column :ai_conversations, :pinned_at, :datetime, null: true
    add_column :ai_conversations, :tags, :jsonb, default: [], null: false

    # Indexes for efficient queries
    add_index :ai_conversations, :pinned_at, where: "pinned_at IS NOT NULL"
    add_index :ai_conversations, :tags, using: :gin

    # Full-text search on message content
    add_column :ai_messages, :search_vector, :tsvector
    add_index :ai_messages, :search_vector, using: :gin

    # Soft-delete for messages
    add_column :ai_messages, :deleted_at, :datetime, null: true
    add_index :ai_messages, :deleted_at, where: "deleted_at IS NOT NULL"

    # Trigger to auto-populate search_vector from content
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION ai_messages_search_vector_update() RETURNS trigger AS $$
          BEGIN
            NEW.search_vector := to_tsvector('english', coalesce(NEW.content, ''));
            RETURN NEW;
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER ai_messages_search_vector_trigger
            BEFORE INSERT OR UPDATE OF content ON ai_messages
            FOR EACH ROW
            EXECUTE FUNCTION ai_messages_search_vector_update();

          UPDATE ai_messages SET search_vector = to_tsvector('english', coalesce(content, ''));
        SQL
      end

      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS ai_messages_search_vector_trigger ON ai_messages;
          DROP FUNCTION IF EXISTS ai_messages_search_vector_update();
        SQL
      end
    end
  end
end
