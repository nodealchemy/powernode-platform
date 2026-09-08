# frozen_string_literal: true

# Environment campaign, increment 1 — give every EXISTING account its default
# environments.
#
# New accounts get them from Account#ensure_default_environments. The installed
# base cannot, because seeds and callbacks only fire for rows created after the
# code landed (the "seeds never re-run after first boot" class). Plain SQL,
# deliberately: a data migration that constantises a model inherits every
# validation and callback that model grows later, and breaks when they change.
#
# The rows mirror Ai::Environment::DEFAULTS. If that table changes, change it
# there — this migration is a one-shot backfill, not a second source of truth.
# Idempotent: ON CONFLICT on (account_id, slug) does nothing.
class SeedDefaultAiEnvironments < ActiveRecord::Migration[8.0]
  DEFAULTS = [
    # slug      name       tier  authority     protected  default  position
    [ "dev",     "Development", 0, "trusted",    false, true,  10 ],
    [ "ci",      "CI",          0, "trusted",    false, false, 20 ],
    [ "staging", "Staging",     1, "trusted",    false, false, 30 ],
    [ "ops",     "Operations",  2, "monitored",  true,  false, 40 ],
    [ "prod",    "Production",  3, "supervised", true,  false, 50 ]
  ].freeze

  def up
    DEFAULTS.each do |slug, name, tier, authority, protected_flag, is_default, position|
      execute <<~SQL.squish
        INSERT INTO ai_environments
          (id, account_id, slug, name, tier, default_decision_authority, is_protected, is_default, position,
           approval_required_categories, metadata, created_at, updated_at)
        SELECT uuidv7(), accounts.id, #{quote(slug)}, #{quote(name)}, #{tier}, #{quote(authority)},
               #{protected_flag}, #{is_default}, #{position}, '[]'::jsonb, '{}'::jsonb, NOW(), NOW()
        FROM accounts
        ON CONFLICT (account_id, slug) DO NOTHING
      SQL
    end
  end

  # Deliberately a no-op. Once these rows exist, templates, nodes, instances,
  # pools and projects reference them, and the Account callback keeps creating
  # them for new accounts; a delete-by-slug here would either FK-fail or remove
  # rows this migration never wrote. Dropping the table (the previous
  # migration's down) is the only honest reversal.
  def down; end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
