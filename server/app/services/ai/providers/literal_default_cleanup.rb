# frozen_string_literal: true

module Ai
  module Providers
    # Clears a provider's configuration_schema "default_model" when ALL of:
    #   1. it is one of the literals the PLATFORM ITSELF once wrote as that
    #      provider type's default;
    #   2. the provider HAS a synced catalog (a non-empty supported_models
    #      array); and
    #   3. that id is absent from it.
    # (Campaign 01a08c9b, E3b.) Condition 2 is the lead's ruling: a never-synced
    # provider's catalog is empty, so "absent" is vacuous there, and clearing a
    # shipped default it is working on would turn it into a refusal at deploy
    # time. Once it syncs, the catalog replaces the stored value on its own terms.
    #
    # Such a value was never an operator's choice. It was stamped by
    # Ai::Provider::Configurable#set_default_configuration_from_type,
    # Ai::ProviderCatalog's configuration_schema or the deleted
    # Ai::Providers::DefaultConfig, and once the synced catalog drops it, it can
    # only route an unpinned caller to a model the provider no longer offers.
    # With it cleared, Provider#default_model picks the lightest-tier catalog
    # model instead. An operator's own default, or a shipped literal the catalog
    # still lists, is left exactly as it is.
    #
    # Two entry points, deliberately different in how far they will go:
    #   - .auto_clear — the data migration. It acts on AUTO_LIMIT rows or fewer,
    #     changes NOTHING above that, and never raises (live nodes apply pending
    #     migrations at boot; a raise would abort db:migrate mid-deploy).
    #   - .operator_run — the rake task. It prints the count and a sample, and
    #     acts only when CONFIRM equals the CURRENT count.
    class LiteralDefaultCleanup
      AUTO_LIMIT = 5
      RAKE_TASK = "ai:clear_literal_provider_defaults"

      # Reused rather than minted: this IS an update of providers, and the
      # change is named in the row's metadata.
      AUDIT_ACTION = "ai.providers.update"
      CHANGE = "literal_default_model_cleared"
      REASON = "The platform once wrote this literal as the provider type's default, and it is absent " \
               "from the provider's synced catalog, so it could only route to a model the provider no " \
               "longer offers. Provider#default_model now picks the lightest-tier catalog model."

      # Every literal the platform shipped as a per-type default, from all three
      # writers named above. The one place these ids are spelled: they are the
      # data this class exists to remove, not a choice anything makes.
      SHIPPED_DEFAULTS = {
        "openai" => %w[gpt-4.1-mini],
        "anthropic" => %w[claude-haiku-4-5],
        "grok" => %w[grok-3-mini],
        "google" => %w[gemini-2.0-flash],
        "groq" => %w[llama-3.3-70b-versatile],
        "mistral" => %w[mistral-large-latest],
        "cohere" => %w[command-r-plus],
        "runway" => %w[gen3a_turbo],
        "elevenlabs" => %w[eleven_multilingual_v2]
      }.freeze

      # The default_model is in the synced catalog when some supported_models
      # entry names it — a bare string, or a hash's "id" falling back to
      # "name", read exactly as Ai::ModelTiers.id_for reads it.
      IN_CATALOG_SQL = <<~SQL.squish.freeze
        EXISTS (
          SELECT 1
          FROM jsonb_array_elements(
                 CASE WHEN jsonb_typeof(ai_providers.supported_models) = 'array'
                      THEN ai_providers.supported_models ELSE '[]'::jsonb END
               ) AS entry
          WHERE COALESCE(entry ->> 'id', entry ->> 'name',
                         CASE WHEN jsonb_typeof(entry) = 'string' THEN entry #>> '{}' END)
                = ai_providers.configuration_schema ->> 'default_model'
        )
      SQL

      # The provider has synced a catalog: a non-empty supported_models array.
      # Neither operand can raise on any jsonb value. Postgres does not
      # short-circuit AND, so jsonb_array_length here would raise on a
      # non-array row and abort the whole cleanup.
      SYNCED_SQL = <<~SQL.squish.freeze
        jsonb_typeof(ai_providers.supported_models) = 'array'
        AND ai_providers.supported_models <> '[]'::jsonb
      SQL

      Outcome = Struct.new(:status, :count, :provider_ids, :message, keyword_init: true)

      class << self
        # The rows this class acts on. Also the source of the read-only count an
        # operator runs before a deploy: matching_scope.select("count(*)").to_sql.
        def matching_scope
          clauses = SHIPPED_DEFAULTS.map do |provider_type, literals|
            ::ActiveRecord::Base.sanitize_sql_array(
              [ "(ai_providers.provider_type = ? AND ai_providers.configuration_schema ->> 'default_model' IN (?))",
                provider_type, literals ]
            )
          end

          ::Ai::Provider.where(clauses.join(" OR "))
                        .where(SYNCED_SQL)
                        .where.not(IN_CATALOG_SQL)
        end

        # [[provider_id, account_id, literal], ...], ordered by id.
        def matching_rows
          matching_scope.order(:id)
                        .pluck(:id, :account_id, Arel.sql("ai_providers.configuration_schema ->> 'default_model'"))
        end

        # The migration's entry point. Never raises.
        def auto_clear(logger: Rails.logger)
          rows = matching_rows

          if rows.size > AUTO_LIMIT
            message = "[E3b] #{rows.size} providers carry a shipped literal default_model that is absent from " \
                      "their synced catalog — more than #{AUTO_LIMIT}, so this migration changed NOTHING. " \
                      "Review them with `bin/rails #{RAKE_TASK}`, then clear them with " \
                      "`bin/rails #{RAKE_TASK} CONFIRM=#{rows.size}`."
            logger.warn(message)
            return Outcome.new(status: :skipped, count: rows.size, provider_ids: [], message: message)
          end

          if rows.empty?
            return Outcome.new(status: :nothing, count: 0, provider_ids: [],
                               message: "[E3b] no provider carries a stale shipped literal default_model")
          end

          clear!(rows)
          ids = rows.map(&:first)
          Outcome.new(status: :cleared, count: ids.size, provider_ids: ids,
                      message: "[E3b] cleared a stale shipped literal default_model on #{ids.size} provider(s)")
        rescue StandardError => e
          message = "[E3b] literal-default cleanup did not run (#{e.class}: #{e.message}); nothing changed. " \
                    "Retry with `bin/rails #{RAKE_TASK}`."
          logger.warn(message)
          Outcome.new(status: :error, count: nil, provider_ids: [], message: message)
        end

        # The rake task's entry point. Acts only on an exact, current CONFIRM.
        def operator_run(confirm:, io: $stdout)
          rows = matching_rows
          ids = rows.map(&:first)

          io.puts "#{ids.size} provider(s) carry a shipped literal default_model that is absent from their synced catalog."
          return Outcome.new(status: :nothing, count: 0, provider_ids: [], message: "nothing to clear") if ids.empty?

          io.puts "  #{sample(ids).join(', ')}"

          if confirm.to_s.strip.empty?
            io.puts "Nothing changed. Re-run with CONFIRM=#{ids.size} to clear them."
            return Outcome.new(status: :unconfirmed, count: ids.size, provider_ids: [], message: "unconfirmed")
          end

          unless confirm.to_s.match?(/\A\d+\z/) && confirm.to_i == ids.size
            io.puts "CONFIRM=#{confirm} does not match the current count (#{ids.size}); nothing changed."
            return Outcome.new(status: :mismatch, count: ids.size, provider_ids: [], message: "mismatch")
          end

          clear!(rows)
          io.puts "Cleared #{ids.size}; one audit row per affected account records each id and the literal it held."
          Outcome.new(status: :cleared, count: ids.size, provider_ids: ids, message: "cleared")
        end

        # The first 3 and the last 1, per the bulk-operation rule.
        def sample(ids)
          ids.size > 4 ? ids.first(3) + [ "…", ids.last ] : ids
        end

        private

        # One transaction: an audit row per affected account first (the
        # audit_logs.account_id column is NOT NULL, so rows from different
        # accounts cannot share one), then the clear. If an audit write fails,
        # nothing is cleared. The key is set to null rather than removed, so
        # set_default_configuration_from_type still sees the shape as written.
        def clear!(rows)
          ::Ai::Provider.transaction do
            rows.group_by { |_id, account_id, _literal| account_id }.each do |account_id, account_rows|
              ::AuditLog.create!(
                account_id: account_id,
                action: AUDIT_ACTION,
                resource_type: "Ai::Provider",
                resource_id: account_rows.first.first,
                source: "system",
                severity: "medium",
                risk_level: "low",
                metadata: {
                  "change" => CHANGE,
                  "reason" => REASON,
                  "cleared" => account_rows.to_h { |id, _account, literal| [ id, literal ] }
                }
              )
            end

            ::Ai::Provider.where(id: rows.map(&:first))
                          .update_all("configuration_schema = jsonb_set(configuration_schema, '{default_model}', 'null'::jsonb)")
          end
        end
      end
    end
  end
end
