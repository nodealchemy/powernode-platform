class AddDiscountsToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :has_annual_discount, :boolean, null: false, default: false
    add_column :plans, :annual_discount_percent, :decimal, precision: 5, scale: 2, default: 0.0
    add_column :plans, :has_volume_discount, :boolean, null: false, default: false
    add_column :plans, :volume_discount_tiers, :text, default: '[]'
    add_column :plans, :has_promotional_discount, :boolean, null: false, default: false
    add_column :plans, :promotional_discount_percent, :decimal, precision: 5, scale: 2, default: 0.0
    add_column :plans, :promotional_discount_start, :datetime
    add_column :plans, :promotional_discount_end, :datetime
    add_column :plans, :promotional_discount_code, :string, limit: 50
    
    # Add indexes for performance
    add_index :plans, :has_annual_discount
    add_index :plans, :has_volume_discount
    add_index :plans, :has_promotional_discount
    add_index :plans, [:promotional_discount_start, :promotional_discount_end]
    add_index :plans, :promotional_discount_code, unique: true, where: "promotional_discount_code IS NOT NULL"
  end
end
