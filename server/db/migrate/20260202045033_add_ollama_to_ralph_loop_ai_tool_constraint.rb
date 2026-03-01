# frozen_string_literal: true

class AddOllamaToRalphLoopAiToolConstraint < ActiveRecord::Migration[8.1]
  def up
    # Remove old constraint
    execute <<-SQL
      ALTER TABLE ai_ralph_loops
      DROP CONSTRAINT IF EXISTS ai_ralph_loops_ai_tool_check;
    SQL

    # Add updated constraint with ollama
    execute <<-SQL
      ALTER TABLE ai_ralph_loops
      ADD CONSTRAINT ai_ralph_loops_ai_tool_check
      CHECK (ai_tool IN ('amp', 'claude_code', 'ollama'));
    SQL
  end

  def down
    # Remove new constraint
    execute <<-SQL
      ALTER TABLE ai_ralph_loops
      DROP CONSTRAINT IF EXISTS ai_ralph_loops_ai_tool_check;
    SQL

    # Restore old constraint
    execute <<-SQL
      ALTER TABLE ai_ralph_loops
      ADD CONSTRAINT ai_ralph_loops_ai_tool_check
      CHECK (ai_tool IN ('amp', 'claude_code'));
    SQL
  end
end
