# frozen_string_literal: true

# E3b (campaign 01a08c9b). Clears a provider's configuration_schema
# "default_model" when it is a literal the platform itself once shipped as that
# provider type's default AND the provider's synced catalog no longer lists it.
#
# Ai::Providers::LiteralDefaultCleanup.auto_clear does the work. It acts on
# AUTO_LIMIT (5) rows or fewer; above that it changes nothing and logs how to
# run `bin/rails ai:clear_literal_provider_defaults CONFIRM=<count>`. It never
# raises, and the rescue here covers the one thing it cannot: failing to load.
# Live nodes apply pending migrations at boot, so a raise would abort a deploy.
class ClearLiteralProviderDefaultModels < ActiveRecord::Migration[8.0]
  # No wrapping transaction. A statement that fails inside one poisons it, so
  # recording this version afterwards would raise even though auto_clear
  # rescued the failure. The clear itself runs in auto_clear's own transaction.
  disable_ddl_transaction!

  def up
    say Ai::Providers::LiteralDefaultCleanup.auto_clear.message
  rescue StandardError => e
    say "[E3b] literal-default cleanup skipped (#{e.class}: #{e.message}); nothing changed. " \
        "Run `bin/rails ai:clear_literal_provider_defaults` to review and clear."
  end

  # Nothing to restore: each cleared literal is kept in an audit row, and
  # putting one back would re-point a provider at a model its catalog no
  # longer lists.
  def down; end
end
