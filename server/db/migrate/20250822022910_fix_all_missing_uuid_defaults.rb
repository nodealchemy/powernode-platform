class FixAllMissingUuidDefaults < ActiveRecord::Migration[8.0]
  def up
    # Get all tables with string ID columns
    tables = ActiveRecord::Base.connection.tables
    
    tables.each do |table_name|
      next if table_name == 'schema_migrations' || table_name == 'ar_internal_metadata'
      
      # Check if table has an id column and if it's a string type
      columns = ActiveRecord::Base.connection.columns(table_name)
      id_column = columns.find { |c| c.name == 'id' }
      
      next unless id_column && id_column.sql_type.include?('character')
      
      # Check if default is already set
      result = execute("SELECT column_default FROM information_schema.columns WHERE table_name = '#{table_name}' AND column_name = 'id'").first
      
      if result.nil? || result['column_default'].nil?
        puts "Adding UUID default to #{table_name}.id"
        execute "ALTER TABLE #{table_name} ALTER COLUMN id SET DEFAULT gen_random_uuid();"
      end
    end
  end
  
  def down
    # Not reversible - we don't want to remove UUID defaults
  end
end
