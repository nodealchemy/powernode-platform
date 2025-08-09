# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_09_060548) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_delegations", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "delegated_user_id", limit: 36, null: false
    t.string "delegated_by_id", limit: 36, null: false
    t.string "role_id", limit: 36
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.string "revoked_by", limit: 36
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "delegated_user_id"], name: "index_account_delegations_on_account_id_and_delegated_user_id", unique: true
    t.index ["account_id"], name: "index_account_delegations_on_account_id"
    t.index ["delegated_by_id"], name: "index_account_delegations_on_delegated_by_id"
    t.index ["delegated_user_id"], name: "index_account_delegations_on_delegated_user_id"
    t.index ["expires_at"], name: "index_account_delegations_on_expires_at"
    t.index ["role_id"], name: "index_account_delegations_on_role_id"
    t.index ["status"], name: "index_account_delegations_on_status"
  end

  create_table "accounts", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "subdomain", limit: 30
    t.string "status", limit: 20, default: "active", null: false
    t.text "settings", default: "{}"
    t.string "stripe_customer_id", limit: 50
    t.string "paypal_customer_id", limit: 50
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["paypal_customer_id"], name: "index_accounts_on_paypal_customer_id", unique: true, where: "(paypal_customer_id IS NOT NULL)"
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["stripe_customer_id"], name: "index_accounts_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["subdomain"], name: "index_accounts_on_subdomain", unique: true, where: "((subdomain IS NOT NULL) AND ((subdomain)::text <> ''::text))"
  end

  create_table "audit_logs", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "user_id", limit: 36
    t.string "account_id", limit: 36, null: false
    t.string "action", limit: 50, null: false
    t.string "resource_type", limit: 100, null: false
    t.string "resource_id", limit: 36, null: false
    t.string "source", limit: 20, default: "web", null: false
    t.text "old_values"
    t.text "new_values"
    t.text "metadata", default: "{}"
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 500
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["resource_id"], name: "index_audit_logs_on_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.index ["resource_type"], name: "index_audit_logs_on_resource_type"
    t.index ["source"], name: "index_audit_logs_on_source"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "blacklisted_tokens", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "token", null: false
    t.string "reason", default: "logout"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["expires_at"], name: "index_blacklisted_tokens_on_expires_at"
    t.index ["token"], name: "index_blacklisted_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "invitations", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "inviter_id", limit: 36, null: false
    t.string "role_id", limit: 36
    t.string "email", limit: 255, null: false
    t.string "first_name", limit: 50
    t.string "last_name", limit: 50
    t.string "token", limit: 255, null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["expires_at"], name: "index_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["role_id"], name: "index_invitations_on_role_id"
    t.index ["status"], name: "index_invitations_on_status"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "invoice_line_items", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "invoice_id", limit: 36, null: false
    t.string "description", limit: 500, null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "line_type", limit: 30, default: "subscription", null: false
    t.date "period_start"
    t.date "period_end"
    t.text "metadata", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
    t.index ["line_type"], name: "index_invoice_line_items_on_line_type"
    t.index ["period_end"], name: "index_invoice_line_items_on_period_end"
    t.index ["period_start"], name: "index_invoice_line_items_on_period_start"
  end

  create_table "invoices", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "subscription_id", limit: 36, null: false
    t.string "invoice_number", limit: 50, null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "status", limit: 30, default: "draft", null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.0", null: false
    t.datetime "due_date"
    t.datetime "paid_at"
    t.text "notes"
    t.text "metadata", default: "{}"
    t.string "stripe_invoice_id", limit: 100
    t.string "paypal_invoice_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["due_date"], name: "index_invoices_on_due_date"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
    t.index ["paid_at"], name: "index_invoices_on_paid_at"
    t.index ["paypal_invoice_id"], name: "index_invoices_on_paypal_invoice_id", unique: true, where: "(paypal_invoice_id IS NOT NULL)"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["stripe_invoice_id"], name: "index_invoices_on_stripe_invoice_id", unique: true, where: "(stripe_invoice_id IS NOT NULL)"
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end

  create_table "password_histories", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_password_histories_on_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "payment_methods", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "user_id", limit: 36, null: false
    t.string "provider", limit: 20, null: false
    t.string "external_id", limit: 100, null: false
    t.string "payment_type", limit: 30, null: false
    t.string "last_four", limit: 4
    t.string "brand", limit: 50
    t.integer "exp_month"
    t.integer "exp_year"
    t.string "holder_name", limit: 100
    t.boolean "is_default", default: false, null: false
    t.text "metadata", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_payment_methods_on_account_id"
    t.index ["external_id"], name: "index_payment_methods_on_external_id"
    t.index ["is_default"], name: "index_payment_methods_on_is_default"
    t.index ["payment_type"], name: "index_payment_methods_on_payment_type"
    t.index ["provider"], name: "index_payment_methods_on_provider"
    t.index ["user_id"], name: "index_payment_methods_on_user_id"
  end

  create_table "payments", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "invoice_id", limit: 36, null: false
    t.bigint "amount_cents", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "payment_method", limit: 50, null: false
    t.string "status", limit: 30, default: "pending", null: false
    t.bigint "gateway_fee_cents", default: 0
    t.bigint "net_amount_cents"
    t.datetime "processed_at"
    t.datetime "failed_at"
    t.text "failure_reason"
    t.text "gateway_response"
    t.text "metadata", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["failed_at"], name: "index_payments_on_failed_at"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["payment_method"], name: "index_payments_on_payment_method"
    t.index ["processed_at"], name: "index_payments_on_processed_at"
    t.index ["status"], name: "index_payments_on_status"
  end

  create_table "permissions", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "name", limit: 100
    t.string "resource", limit: 50, null: false
    t.string "action", limit: 50, null: false
    t.string "description", limit: 255
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_permissions_on_action"
    t.index ["name"], name: "index_permissions_on_name", unique: true, where: "(name IS NOT NULL)"
    t.index ["resource", "action"], name: "index_permissions_on_resource_and_action", unique: true
    t.index ["resource"], name: "index_permissions_on_resource"
  end

  create_table "plans", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "description", limit: 500
    t.bigint "price_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.string "billing_cycle", limit: 20, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.integer "trial_days", default: 0, null: false
    t.boolean "is_public", default: true, null: false
    t.text "features", default: "{}"
    t.text "limits", default: "{}"
    t.text "metadata", default: "{}"
    t.string "stripe_price_id", limit: 100
    t.string "paypal_plan_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_cycle"], name: "index_plans_on_billing_cycle"
    t.index ["currency"], name: "index_plans_on_currency"
    t.index ["is_public"], name: "index_plans_on_is_public"
    t.index ["paypal_plan_id"], name: "index_plans_on_paypal_plan_id", unique: true, where: "(paypal_plan_id IS NOT NULL)"
    t.index ["status"], name: "index_plans_on_status"
    t.index ["stripe_price_id"], name: "index_plans_on_stripe_price_id", unique: true, where: "(stripe_price_id IS NOT NULL)"
  end

  create_table "revenue_snapshots", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36
    t.date "snapshot_date", null: false
    t.bigint "mrr_cents", default: 0, null: false
    t.bigint "arr_cents", default: 0, null: false
    t.integer "active_subscriptions", default: 0, null: false
    t.integer "new_subscriptions", default: 0, null: false
    t.integer "churned_subscriptions", default: 0, null: false
    t.integer "upgraded_subscriptions", default: 0, null: false
    t.integer "downgraded_subscriptions", default: 0, null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.text "metadata", default: "{}"
    t.datetime "created_at", null: false
    t.index ["account_id", "snapshot_date"], name: "index_revenue_snapshots_on_account_id_and_snapshot_date", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["account_id"], name: "index_revenue_snapshots_on_account_id"
    t.index ["currency"], name: "index_revenue_snapshots_on_currency"
    t.index ["snapshot_date"], name: "index_revenue_snapshots_on_global_snapshot_date", unique: true, where: "(account_id IS NULL)"
    t.index ["snapshot_date"], name: "index_revenue_snapshots_on_snapshot_date"
  end

  create_table "role_permissions", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "role_id", limit: 36, null: false
    t.string "permission_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "name", limit: 50, null: false
    t.string "description", limit: 255
    t.boolean "system_role", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
    t.index ["system_role"], name: "index_roles_on_system_role"
  end

  create_table "subscriptions", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "plan_id", limit: 36, null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", limit: 30, default: "trialing", null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "trial_start"
    t.datetime "trial_end"
    t.datetime "canceled_at"
    t.datetime "ended_at"
    t.text "metadata", default: "{}"
    t.string "stripe_subscription_id", limit: 100
    t.string "paypal_subscription_id", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_subscriptions_on_account_id", unique: true
    t.index ["current_period_end"], name: "index_subscriptions_on_current_period_end"
    t.index ["paypal_subscription_id"], name: "index_subscriptions_on_paypal_subscription_id", unique: true, where: "(paypal_subscription_id IS NOT NULL)"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_end"], name: "index_subscriptions_on_trial_end"
  end

  create_table "user_roles", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "user_id", limit: 36, null: false
    t.string "role_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36, null: false
    t.string "email", limit: 255, null: false
    t.string "password_digest", null: false
    t.string "first_name", limit: 50, null: false
    t.string "last_name", limit: 50, null: false
    t.string "status", limit: 20, default: "active", null: false
    t.boolean "email_verified", default: false, null: false
    t.datetime "email_verified_at"
    t.string "email_verification_token", limit: 255
    t.datetime "email_verification_token_expires_at"
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "password_changed_at"
    t.datetime "last_login_at"
    t.string "last_login_ip", limit: 45
    t.string "reset_token_digest"
    t.datetime "reset_token_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true, where: "(email_verification_token IS NOT NULL)"
    t.index ["reset_token_digest"], name: "index_users_on_reset_token_digest", unique: true, where: "(reset_token_digest IS NOT NULL)"
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "webhook_events", id: { type: :string, limit: 36 }, force: :cascade do |t|
    t.string "account_id", limit: 36
    t.string "provider", limit: 20, null: false
    t.string "event_type", limit: 100, null: false
    t.string "external_id", limit: 100, null: false
    t.text "payload", null: false
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "processed_at"
    t.text "error_message"
    t.integer "retry_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_webhook_events_on_account_id"
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
    t.index ["external_id"], name: "index_webhook_events_on_external_id"
    t.index ["provider", "external_id"], name: "index_webhook_events_on_provider_and_external_id", unique: true
    t.index ["provider"], name: "index_webhook_events_on_provider"
    t.index ["status"], name: "index_webhook_events_on_status"
  end

  add_foreign_key "account_delegations", "accounts"
  add_foreign_key "account_delegations", "roles", on_delete: :nullify
  add_foreign_key "account_delegations", "users", column: "delegated_by_id"
  add_foreign_key "account_delegations", "users", column: "delegated_user_id"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "roles", on_delete: :nullify
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "password_histories", "users"
  add_foreign_key "payment_methods", "accounts"
  add_foreign_key "payment_methods", "users"
  add_foreign_key "payments", "invoices"
  add_foreign_key "revenue_snapshots", "accounts", on_delete: :cascade
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "subscriptions", "accounts"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "accounts"
  add_foreign_key "webhook_events", "accounts", on_delete: :nullify
end
