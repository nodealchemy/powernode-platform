# frozen_string_literal: true

class FixUuidDefaultsForAllTables < ActiveRecord::Migration[8.0]
  def up
    # Get all tables that have string id columns without proper defaults
    tables_to_fix = %w[
      accounts plans subscriptions users payment_methods invoices
      payments webhooks webhook_events audit_logs workers volumes
      usage_snapshots notifications pages password_histories
      impersonation_sessions account_invitations account_delegations
      api_keys kb_articles kb_categories
    ]
    
    tables_to_fix.each do |table_name|
      next unless table_exists?(table_name)
      
      # Check if the table has a string id column
      column = columns(table_name).find { |c| c.name == 'id' }
      next unless column && column.type == :string
      
      # Update the default value to use gen_random_uuid()
      execute <<-SQL
        ALTER TABLE #{table_name} 
        ALTER COLUMN id SET DEFAULT gen_random_uuid()
      SQL
      
      puts "Updated #{table_name} to use gen_random_uuid() for id column"
    end
  end
  
  def down
    # Revert to no default (ApplicationRecord was handling it)
    tables_to_fix = %w[
      accounts plans subscriptions users payment_methods invoices
      payments webhooks webhook_events audit_logs workers volumes
      usage_snapshots notifications pages password_histories
      impersonation_sessions account_invitations account_delegations
      api_keys kb_articles kb_categories
    ]
    
    tables_to_fix.each do |table_name|
      next unless table_exists?(table_name)
      
      column = columns(table_name).find { |c| c.name == 'id' }
      next unless column && column.type == :string
      
      execute <<-SQL
        ALTER TABLE #{table_name} 
        ALTER COLUMN id DROP DEFAULT
      SQL
    end
  end
end