# frozen_string_literal: true

# Makes Ai::DataSource generic: the model drops the hardcoded source_type
# enum (now any lowercase token is allowed) and gains a free-form +category+
# grouping, while endpoints gain outbound +pagination+ config.
#
#   - ai_data_sources.category (string, limit 100): coarse grouping for the
#     UI / scoping (e.g. "weather", "finance", "sports", "news"). Nullable —
#     "custom"/unknown sources have no canonical category. Backfilled from the
#     legacy source_type tokens below. A partial index (NULLs excluded) keeps
#     the by_category scope fast without indexing the large unset tail.
#   - ai_data_source_endpoints.pagination (jsonb default {}): outbound
#     pagination config consumed by the REST adapter / QueryService. Default
#     {} == OFF (single request, unchanged behavior). No index — config blob
#     read alongside its endpoint row, never queried in isolation (mirrors the
#     contract / response_mapping jsonb columns).
#
# Reversible: down drops both columns (the partial index drops with the column).
# The category backfill is a data-only step inside the same change block,
# guarded by a reversible block so a rollback is a clean column drop.
class GeneralizeAiDataSourceWithCategory < ActiveRecord::Migration[8.0]
  # Legacy source_type -> category mapping (CONTRACT). Tokens not listed
  # (e.g. "custom" or any later free-form token) intentionally stay NULL.
  SOURCE_TYPE_CATEGORY = {
    "noaa_ncei" => "weather",
    "noaa_gfs" => "weather",
    "noaa_observations" => "weather",
    "open_meteo" => "weather",
    "fred" => "finance",
    "yahoo_finance" => "finance",
    "espn" => "sports",
    "newsapi" => "news"
  }.freeze

  def change
    add_column :ai_data_sources, :category, :string, limit: 100
    add_column :ai_data_source_endpoints, :pagination, :jsonb, default: {}

    # Partial index: only rows with a category participate (the by_category
    # scope never matches NULL), so the unset tail costs nothing.
    add_index :ai_data_sources, :category,
              name: "index_ai_data_sources_on_category",
              where: "category IS NOT NULL"

    # Backfill category from the legacy source_type tokens. up = populate,
    # down = no-op (the column — and its data — is dropped by the add_column
    # reversal above, so there is nothing to undo here).
    reversible do |dir|
      dir.up do
        SOURCE_TYPE_CATEGORY.each do |source_type, category|
          execute(<<~SQL.squish)
            UPDATE ai_data_sources
            SET category = #{quote(category)}
            WHERE source_type = #{quote(source_type)}
              AND category IS NULL
          SQL
        end
      end
    end
  end
end
