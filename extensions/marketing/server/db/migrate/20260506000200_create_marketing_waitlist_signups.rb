# frozen_string_literal: true

class CreateMarketingWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    create_table :marketing_waitlist_signups, id: :uuid do |t|
      t.string :email, null: false
      t.string :source                         # homepage, pricing, features, blog, docs, etc.
      t.string :ip_address
      t.string :user_agent
      t.string :referrer
      t.jsonb :metadata, default: {}           # UTM params, A/B variant, etc.

      # Optional links: nurture infrastructure (set after sync) and account (set after conversion).
      # Lead capture is anonymous so account_id is NOT required at insert time.
      t.references :email_subscriber,
        foreign_key: { to_table: :marketing_email_subscribers, on_delete: :nullify },
        type: :uuid, index: true, null: true
      t.references :converted_account,
        foreign_key: { to_table: :accounts, on_delete: :nullify },
        type: :uuid, index: true, null: true

      # Double opt-in pattern (mirrors marketing_email_subscribers conventions)
      t.string :status, default: "pending"     # pending, confirmed, unsubscribed
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :unsubscribed_at
      t.datetime :converted_at                 # when converted_account_id was set

      t.timestamps
    end

    add_index :marketing_waitlist_signups, :email, unique: true
    add_index :marketing_waitlist_signups, :status
    add_index :marketing_waitlist_signups, :source
    add_index :marketing_waitlist_signups, :confirmation_token,
      unique: true, where: "confirmation_token IS NOT NULL"

    add_check_constraint :marketing_waitlist_signups,
      "status IN ('pending', 'confirmed', 'unsubscribed')",
      name: "marketing_waitlist_signups_status_check"
  end
end
