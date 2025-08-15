class AddTwoFactorToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :two_factor_enabled, :boolean, default: false, null: false
    add_column :users, :two_factor_secret, :string
    add_column :users, :backup_codes, :text
    add_column :users, :two_factor_backup_codes_generated_at, :datetime
    add_column :users, :two_factor_enabled_at, :datetime
    
    # Add index for performance on 2FA lookups
    add_index :users, :two_factor_enabled
  end
end
