class AddUuidDefaultToAdminSettings < ActiveRecord::Migration[8.0]
  def change
    # Add UUID generation default to admin_settings and other tables that need it
    execute <<-SQL
      ALTER TABLE admin_settings ALTER COLUMN id SET DEFAULT gen_random_uuid();
    SQL
    
    # Fix other tables that might be missing UUID defaults
    tables_needing_uuid = %w[api_tokens session_tokens audit_logs]
    
    tables_needing_uuid.each do |table_name|
      if table_exists?(table_name) && column_exists?(table_name, :id)
        result = execute("SELECT column_default FROM information_schema.columns WHERE table_name = '#{table_name}' AND column_name = 'id'").first
        if result.nil? || result['column_default'].nil?
          execute "ALTER TABLE #{table_name} ALTER COLUMN id SET DEFAULT gen_random_uuid();"
        end
      end
    end
  end
end
