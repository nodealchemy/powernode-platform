# frozen_string_literal: true

# Migration to standardize audit log action names from legacy underscore-separated
# format to the new dot-notation format (e.g., ai_agents.create -> ai.agents.create)
class StandardizeAuditLogActions < ActiveRecord::Migration[7.1]
  # Disable DDL transaction since this is a data migration that may take time
  disable_ddl_transaction!

  # Legacy action mappings from AuditActions::MIGRATION_MAPPINGS
  MIGRATION_MAPPINGS = {
    # AI Agents legacy -> standardized
    'ai_agents.index' => 'ai.agents.read',
    'ai_agents.create' => 'ai.agents.create',
    'ai_agents.update' => 'ai.agents.update',
    'ai_agents.destroy' => 'ai.agents.delete',
    'ai_agents.execute' => 'ai.agents.execute',
    'ai_agents.clone' => 'ai.agents.clone',
    'ai_agents.pause' => 'ai.agents.pause',
    'ai_agents.resume' => 'ai.agents.resume',
    'ai_agents.archive' => 'ai.agents.archive',
    'ai_agents.stats' => 'ai.agents.stats',
    'ai_agents.analytics' => 'ai.agents.analytics',

    # AI Conversations legacy -> standardized
    'ai_conversations.create' => 'ai.conversations.create',
    'ai_conversations.update' => 'ai.conversations.update',
    'ai_conversations.destroy' => 'ai.conversations.delete',

    # AI Messages legacy -> standardized
    'ai_messages.create' => 'ai.messages.create',
    'ai_messages.update' => 'ai.messages.update',
    'ai_messages.destroy' => 'ai.messages.delete',
    'ai_messages.edit_content' => 'ai.messages.edit_content',

    # AI Analytics legacy -> standardized
    'ai_analytics.usage_recorded' => 'ai.analytics.usage_recorded',
    'ai_analytics.update' => 'ai.analytics.update'
  }.freeze

  def up
    say_with_time 'Standardizing audit log action names' do
      total_updated = 0

      MIGRATION_MAPPINGS.each do |old_action, new_action|
        # Use batch updates to avoid memory issues with large tables
        loop do
          updated = execute_update(old_action, new_action, batch_size: 10_000)
          total_updated += updated
          break if updated < 10_000
        end
      end

      say "Total records updated: #{total_updated}"
      total_updated
    end
  end

  def down
    say_with_time 'Reverting audit log action names to legacy format' do
      total_updated = 0

      # Reverse the mappings
      MIGRATION_MAPPINGS.each do |old_action, new_action|
        loop do
          updated = execute_update(new_action, old_action, batch_size: 10_000)
          total_updated += updated
          break if updated < 10_000
        end
      end

      say "Total records reverted: #{total_updated}"
      total_updated
    end
  end

  private

  def execute_update(from_action, to_action, batch_size:)
    # Use raw SQL with a subquery to limit batch size
    result = execute(<<~SQL)
      UPDATE audit_logs
      SET action = '#{to_action}'
      WHERE id IN (
        SELECT id FROM audit_logs
        WHERE action = '#{from_action}'
        LIMIT #{batch_size}
      )
    SQL

    result.cmd_tuples
  end
end
