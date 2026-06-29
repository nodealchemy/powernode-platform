# frozen_string_literal: true

# Expand-contract, additive + reversible: generalize ai_campaign_lands into a
# polymorphic land source so the canonical land path can land Missions (and any
# future landable) alongside Campaigns. The legacy campaign_id stays populated
# for existing rows (and for new campaign lands) — this migration only ADDS the
# generic seam and relaxes the NOT NULL so non-campaign sources can exist.
class AddSourceToAiCampaignLands < ActiveRecord::Migration[8.0]
  def up
    add_column :ai_campaign_lands, :source_type, :string
    add_column :ai_campaign_lands, :source_id, :uuid

    # Backfill the polymorphic source from the existing campaign_id so every
    # legacy row resolves through the new generic seam without a model fallback.
    execute(<<~SQL.squish)
      UPDATE ai_campaign_lands
      SET source_type = 'Ai::Campaign', source_id = campaign_id
      WHERE source_id IS NULL AND campaign_id IS NOT NULL
    SQL

    # Non-campaign land sources (e.g. Missions) leave campaign_id NULL.
    change_column_null :ai_campaign_lands, :campaign_id, true

    add_index :ai_campaign_lands, [ :source_type, :source_id ],
              name: "index_ai_campaign_lands_on_source"
  end

  def down
    # Reversible only while every row is still a campaign land; otherwise
    # restoring the NOT NULL constraint would drop the non-campaign sources.
    if connection.select_value("SELECT 1 FROM ai_campaign_lands WHERE campaign_id IS NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "ai_campaign_lands has rows with NULL campaign_id (non-campaign land sources); " \
            "cannot restore the campaign_id NOT NULL constraint."
    end

    remove_index :ai_campaign_lands, name: "index_ai_campaign_lands_on_source"
    change_column_null :ai_campaign_lands, :campaign_id, false
    remove_column :ai_campaign_lands, :source_id
    remove_column :ai_campaign_lands, :source_type
  end
end
