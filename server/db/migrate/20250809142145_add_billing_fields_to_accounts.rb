class AddBillingFieldsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :billing_email, :string
    add_column :accounts, :tax_id, :string
  end
end
