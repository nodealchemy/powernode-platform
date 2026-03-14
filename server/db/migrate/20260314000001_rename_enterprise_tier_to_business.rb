# frozen_string_literal: true

class RenameEnterpriseTierToBusiness < ActiveRecord::Migration[8.0]
  def up
    # Update CHECK constraints to use 'business' instead of 'enterprise'
    remove_check_constraint :accounts, name: "check_analytics_tier"
    add_check_constraint :accounts,
      "analytics_tier::text = ANY (ARRAY['free','starter','pro','business']::text[])",
      name: "check_analytics_tier"

    remove_check_constraint :ai_agent_templates, name: "check_template_visibility"
    add_check_constraint :ai_agent_templates,
      "visibility::text = ANY (ARRAY['private','unlisted','public','business']::text[])",
      name: "check_template_visibility"

    remove_check_constraint :ai_credit_packs, name: "check_credit_pack_type"
    add_check_constraint :ai_credit_packs,
      "pack_type::text = ANY (ARRAY['standard','bulk','business','promotional','reseller']::text[])",
      name: "check_credit_pack_type"

    remove_check_constraint :baas_tenants, name: "baas_tenants_tier_check"
    add_check_constraint :baas_tenants,
      "tier::text = ANY (ARRAY['free','starter','pro','business']::text[])",
      name: "baas_tenants_tier_check"

    remove_check_constraint :webhook_endpoints, name: "check_webhook_tier"
    add_check_constraint :webhook_endpoints,
      "tier::text = ANY (ARRAY['free','pro','business']::text[])",
      name: "check_webhook_tier"

    # Update existing data rows
    execute "UPDATE accounts SET analytics_tier = 'business' WHERE analytics_tier = 'enterprise'"
    execute "UPDATE ai_agent_templates SET visibility = 'business' WHERE visibility = 'enterprise'"
    execute "UPDATE ai_credit_packs SET pack_type = 'business' WHERE pack_type = 'enterprise'"
    execute "UPDATE baas_tenants SET tier = 'business' WHERE tier = 'enterprise'"
    execute "UPDATE webhook_endpoints SET tier = 'business' WHERE tier = 'enterprise'"
    execute "UPDATE ai_agent_installations SET license_type = 'business' WHERE license_type = 'enterprise'"
    execute "UPDATE marketplace_subscriptions SET tier = 'business' WHERE tier = 'enterprise'"

    # Rename Flipper feature flags (idempotent: delete old if new already exists)
    execute "DELETE FROM flipper_gates WHERE feature_key = 'enterprise_mode'"
    execute "DELETE FROM flipper_features WHERE key = 'enterprise_mode'"
    execute <<~SQL
      INSERT INTO flipper_features (key, created_at, updated_at)
      SELECT 'business_mode', NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM flipper_features WHERE key = 'business_mode')
    SQL

    # Rename remaining enterprise_* feature flags to business_*
    execute <<~SQL
      DELETE FROM flipper_gates WHERE feature_key LIKE 'enterprise_%'
    SQL
    execute <<~SQL
      DELETE FROM flipper_features WHERE key LIKE 'enterprise_%'
    SQL

    # Rename AI skill categories
    execute "UPDATE ai_skills SET category = 'business_search' WHERE category = 'enterprise_search'"
  end

  def down
    # Reverse CHECK constraints
    remove_check_constraint :accounts, name: "check_analytics_tier"
    add_check_constraint :accounts,
      "analytics_tier::text = ANY (ARRAY['free','starter','pro','enterprise']::text[])",
      name: "check_analytics_tier"

    remove_check_constraint :ai_agent_templates, name: "check_template_visibility"
    add_check_constraint :ai_agent_templates,
      "visibility::text = ANY (ARRAY['private','unlisted','public','enterprise']::text[])",
      name: "check_template_visibility"

    remove_check_constraint :ai_credit_packs, name: "check_credit_pack_type"
    add_check_constraint :ai_credit_packs,
      "pack_type::text = ANY (ARRAY['standard','bulk','enterprise','promotional','reseller']::text[])",
      name: "check_credit_pack_type"

    remove_check_constraint :baas_tenants, name: "baas_tenants_tier_check"
    add_check_constraint :baas_tenants,
      "tier::text = ANY (ARRAY['free','starter','pro','enterprise']::text[])",
      name: "baas_tenants_tier_check"

    remove_check_constraint :webhook_endpoints, name: "check_webhook_tier"
    add_check_constraint :webhook_endpoints,
      "tier::text = ANY (ARRAY['free','pro','enterprise']::text[])",
      name: "check_webhook_tier"

    # Reverse data updates
    execute "UPDATE accounts SET analytics_tier = 'enterprise' WHERE analytics_tier = 'business'"
    execute "UPDATE ai_agent_templates SET visibility = 'enterprise' WHERE visibility = 'business'"
    execute "UPDATE ai_credit_packs SET pack_type = 'enterprise' WHERE pack_type = 'business'"
    execute "UPDATE baas_tenants SET tier = 'enterprise' WHERE tier = 'business'"
    execute "UPDATE webhook_endpoints SET tier = 'enterprise' WHERE tier = 'business'"
    execute "UPDATE ai_agent_installations SET license_type = 'enterprise' WHERE license_type = 'business'"
    execute "UPDATE marketplace_subscriptions SET tier = 'enterprise' WHERE tier = 'business'"

    # Reverse Flipper flags
    execute "UPDATE flipper_features SET key = 'enterprise_mode' WHERE key = 'business_mode'"
    execute "UPDATE flipper_gates SET feature_key = 'enterprise_mode' WHERE feature_key = 'business_mode'"

    execute <<~SQL
      UPDATE flipper_features
      SET key = 'enterprise' || substr(key, length('business') + 1)
      WHERE key LIKE 'business_%' AND key != 'business_mode'
    SQL
    execute <<~SQL
      UPDATE flipper_gates
      SET feature_key = 'enterprise' || substr(feature_key, length('business') + 1)
      WHERE feature_key LIKE 'business_%' AND feature_key != 'business_mode'
    SQL

    execute "UPDATE ai_skills SET category = 'enterprise_search' WHERE category = 'business_search'"
  end
end
