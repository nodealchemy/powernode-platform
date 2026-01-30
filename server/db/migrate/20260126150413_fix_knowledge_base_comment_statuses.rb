# frozen_string_literal: true

class FixKnowledgeBaseCommentStatuses < ActiveRecord::Migration[8.1]
  def up
    # Update existing data: published → approved, hidden → rejected
    execute <<-SQL
      UPDATE knowledge_base_comments SET status = 'approved' WHERE status = 'published';
      UPDATE knowledge_base_comments SET status = 'rejected' WHERE status = 'hidden';
    SQL

    # Remove old CHECK constraint
    execute <<-SQL
      ALTER TABLE knowledge_base_comments DROP CONSTRAINT IF EXISTS valid_kb_comment_status;
    SQL

    # Add corrected CHECK constraint
    execute <<-SQL
      ALTER TABLE knowledge_base_comments
        ADD CONSTRAINT valid_kb_comment_status
        CHECK (status IN ('pending', 'approved', 'rejected', 'spam'));
    SQL

    # Change default from 'published' to 'pending'
    change_column_default :knowledge_base_comments, :status, from: "published", to: "pending"
  end

  def down
    # Reverse data changes
    execute <<-SQL
      UPDATE knowledge_base_comments SET status = 'published' WHERE status = 'approved';
      UPDATE knowledge_base_comments SET status = 'hidden' WHERE status = 'rejected';
    SQL

    execute <<-SQL
      ALTER TABLE knowledge_base_comments DROP CONSTRAINT IF EXISTS valid_kb_comment_status;
    SQL

    execute <<-SQL
      ALTER TABLE knowledge_base_comments
        ADD CONSTRAINT valid_kb_comment_status
        CHECK (status IN ('pending', 'published', 'hidden', 'spam'));
    SQL

    change_column_default :knowledge_base_comments, :status, from: "pending", to: "published"
  end
end
