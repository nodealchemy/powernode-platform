class CreateImpersonationSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :impersonation_sessions, id: { type: :string, limit: 36 } do |t|
      t.string :impersonator_id, limit: 36, null: false
      t.string :impersonated_user_id, limit: 36, null: false
      t.string :account_id, limit: 36, null: false
      t.string :session_token, null: false, index: { unique: true }
      t.string :reason, limit: 500
      t.timestamp :started_at, null: false
      t.timestamp :ended_at
      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 500
      t.boolean :active, default: true, null: false

      t.timestamps

      t.index [ :impersonator_id, :active ]
      t.index [ :impersonated_user_id, :active ]
      t.index [ :account_id, :active ]
      t.index :started_at
    end

    add_foreign_key :impersonation_sessions, :users, column: :impersonator_id
    add_foreign_key :impersonation_sessions, :users, column: :impersonated_user_id
    add_foreign_key :impersonation_sessions, :accounts, column: :account_id

    add_check_constraint :impersonation_sessions,
      'impersonator_id != impersonated_user_id',
      name: 'prevent_self_impersonation'
  end
end
