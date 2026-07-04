# frozen_string_literal: true

module Ai
  module DataSources
    # Onboarding portability for data sources — the "config not code / generic +
    # evolving" story. Turns a configured Ai::DataSource (+ its endpoints) into a
    # CREDENTIAL-FREE, portable MANIFEST and back, plus append-only config
    # versioning + rollback on top of Ai::DataSourceConfigVersion.
    #
    # ── ABSOLUTE SECURITY CONSTRAINT ──────────────────────────────────────────
    # The export manifest is CREDENTIAL-FREE. It MUST NEVER contain:
    #   - decrypted secrets, API keys, passwords, tokens, mnemonics
    #   - Ai::DataSourceCredential records (the credentials association is NOT
    #     traversed)
    #   - any encrypted/secret column
    #   - Vault paths/handles that resolve to secret MATERIAL, or any auth_config
    #     SECRET value (client_secret, web_identity_token JWT, api_key, ...)
    # It MAY carry the auth_scheme NAME and NON-secret broker config knobs
    # (token_url, role_arn, region, scope, ...). Credentials are added SEPARATELY
    # after import — #import NEVER sets credentials.
    #
    # ── MANIFEST SHAPE ────────────────────────────────────────────────────────
    #   {
    #     "manifest_version" => 1,
    #     "source" => {            # SOURCE_EXPORT_KEYS only (see below)
    #       "name", "slug", "source_type", "category", "protocol",
    #       "api_base_url", "description", "documentation_url",
    #       "is_active", "requires_auth", "respect_robots", "crawl_delay_seconds",
    #       "priority_order", "capabilities", "configuration", "rate_limits",
    #       "default_parameters", "metadata",
    #       "auth_scheme",         # NAME only
    #       "auth_config"          # SANITIZED — non-secret knobs only (may be {})
    #     },
    #     "endpoints" => [ {       # ENDPOINT_EXPORT_KEYS only (see below)
    #       "name", "slug", "http_method", "path_template",
    #       "response_format", "expected_content_type", "cache_ttl_seconds",
    #       "monitorable", "change_detection",
    #       "query_template", "body_template", "response_mapping",
    #       "response_schema", "pagination", "incremental", "transforms",
    #       "metadata"
    #     }, ... ],
    #     "exported_at" => nil     # caller stamps (kept nil so the manifest is
    #                              # byte-stable / diffable across exports)
    #   }
    #
    # ── EXCLUDED FROM EXPORT (never serialized) ───────────────────────────────
    #   id, account_id, created_at, updated_at, health_status,
    #   last_health_check_at, last_used_at, effectiveness_score, usage_count,
    #   positive_usage_count, negative_usage_count  (identity + runtime/usage
    #   state), the ENTIRE credentials association, and any secret-ish auth_config
    #   value. Endpoints likewise drop id/ai_data_source_id/timestamps plus the
    #   runtime cursor/etag/last_modified/contract columns.
    class ConfigPortabilityService
      MANIFEST_VERSION = 1

      # ── ALLOWLIST: portable, NON-secret source attributes ──────────────────
      # auth_config is handled SEPARATELY via #sanitize_auth_config (sanitized),
      # so it is intentionally NOT in this plain copy list.
      SOURCE_EXPORT_KEYS = %w[
        name slug source_type category protocol api_base_url description
        documentation_url is_active requires_auth respect_robots
        crawl_delay_seconds priority_order capabilities configuration
        rate_limits default_parameters metadata auth_scheme
      ].freeze

      # ── ALLOWLIST: portable, NON-secret endpoint attributes ────────────────
      ENDPOINT_EXPORT_KEYS = %w[
        name slug http_method path_template response_format
        expected_content_type cache_ttl_seconds monitorable change_detection
        query_template body_template response_mapping response_schema
        pagination incremental transforms metadata
      ].freeze

      # ── ALLOWLIST: NON-secret auth_config knobs that MAY ride the manifest ──
      # Union of every documented broker's NON-secret config (oauth2 client
      # credentials, oauth2 authorization code, aws_sts, aws_sts_web_identity,
      # vault_dynamic) PLUS the flat SigV4 knobs (region/service) some sources
      # set directly on auth_config.
      # CRITICAL: this is an ALLOWLIST — anything not listed is DROPPED. Even so,
      # each value is additionally screened by #secret_key? (defense in depth) so
      # a knob that ever turns secret-ish is still stripped. Secret-bearing keys
      # NEVER appear here: client_secret/api_key/password/token/web_identity_token
      # (raw JWT)/secret/key/... live off the credential record, not config.
      # NOTE: external_id is deliberately EXCLUDED — an AWS STS external_id is a
      # confused-deputy SHARED SECRET (the importing operator re-supplies it with the
      # credential), not a portable structural knob.
      # authorize_url is the OAuth2 Authorization-Code grant's user-facing consent
      # URL (OauthAuthorizationCodeService#build_authorize_request) — a public,
      # documented provider endpoint, never secret-bearing.
      AUTH_CONFIG_ALLOWED_KEYS = %w[
        type token_url authorize_url scope audience client_auth skew_seconds
        role_arn session_name duration_seconds region service vault_path
        path lease_seconds ttl token_request_method token_file
      ].freeze

      # ── DENYLIST: substrings that mark a key as secret-bearing ─────────────
      # Applied to every auth_config key (nested too) on top of the allowlist as
      # defense in depth. A key matching ANY of these is dropped regardless of the
      # allowlist. NOTE token_file (a PATH, not material) is allowlisted above and
      # survives because we screen on these substrings, none of which it contains;
      # "token_url"/"token_request_method" likewise contain "token" but are
      # allowlisted AND do not match a denied substring on their own — see
      # #secret_key? for the exact-token guard that keeps a bare "token" out.
      SECRET_KEY_SUBSTRINGS = %w[
        secret password passwd credential private mnemonic seed_phrase
        access_key secret_key client_secret api_secret web_identity_token
      ].freeze

      # Exact key names that are ALWAYS secret even though their substring is not
      # caught above (e.g. a bare "token" / "key" / "apikey" / "api_key").
      SECRET_KEY_EXACT = %w[
        token key apikey api_key auth jwt bearer signature passphrase
      ].freeze

      # @param account [Account] the account every import/snapshot is scoped to.
      def initialize(account:)
        @account = account
      end

      # ── EXPORT ─────────────────────────────────────────────────────────────
      # Build a CREDENTIAL-FREE manifest Hash for +data_source+. Never traverses
      # the credentials association; auth_config is sanitized to non-secret knobs
      # only. "exported_at" is left nil for the caller to stamp (keeps the
      # manifest byte-stable across exports so versions diff cleanly).
      #
      # @param data_source [Ai::DataSource]
      # @return [Hash] string-keyed manifest (see class doc for the exact shape).
      def export(data_source)
        {
          "manifest_version" => MANIFEST_VERSION,
          "source" => export_source(data_source),
          "endpoints" => export_endpoints(data_source),
          "exported_at" => nil
        }
      end

      # ── IMPORT ─────────────────────────────────────────────────────────────
      # Create-or-update a DataSource (+ endpoints) in @account from +manifest+.
      # The source is found_or_initialized by slug (the manifest's, or an explicit
      # override); endpoints are upserted by slug. NEVER sets credentials — those
      # are added separately after import.
      #
      # @param manifest [Hash] a manifest produced by #export (string OR symbol
      #   keys tolerated).
      # @param slug [String, nil] override for the target source slug (defaults to
      #   the manifest's source slug).
      # @param dry_run [Boolean] when true, persist NOTHING and return a preview
      #   of what WOULD be created/updated.
      # @return [Hash] {
      #   data_source:        the persisted (or, on dry_run, in-memory) source,
      #   created:            Boolean — was the source newly created?,
      #   updated_endpoints:  Array<Hash> — per-endpoint {slug:, action:} outcome,
      #   dry_run:            Boolean,
      #   errors:             Array<String>
      # }
      def import(manifest, slug: nil, dry_run: false)
        manifest = normalize_manifest(manifest)
        source_attrs = sanitized_source_attrs(manifest["source"])
        target_slug = (slug.presence || source_attrs["slug"]).to_s.strip

        if target_slug.blank?
          return import_error("manifest source is missing a slug", dry_run: dry_run)
        end

        data_source = @account.ai_data_sources.find_or_initialize_by(slug: target_slug)
        created = data_source.new_record?
        # Force the resolved slug (covers an explicit override AND a brand-new
        # record whose slug would otherwise be auto-generated from the name).
        apply_source_attrs(data_source, source_attrs, target_slug, created)

        if dry_run
          return import_preview(data_source, created, manifest["endpoints"])
        end

        persist_import(data_source, created, manifest["endpoints"])
      rescue StandardError => e
        Rails.logger.error("[ConfigPortabilityService] import failed: #{e.class}: #{e.message}")
        import_error("import failed: #{e.message}", dry_run: dry_run)
      end

      # ── SNAPSHOT ───────────────────────────────────────────────────────────
      # Persist a DataSourceConfigVersion capturing the CURRENT #export of
      # +data_source+ at the next sequential version number.
      #
      # @param data_source [Ai::DataSource]
      # @param created_by_type [String] "manual" | "auto" | "rollback".
      # @param note [String, nil] optional human note.
      # @return [Ai::DataSourceConfigVersion] the persisted version record.
      def snapshot!(data_source, created_by_type: "manual", note: nil)
        persist_manifest_snapshot(
          data_source,
          export(data_source).merge("exported_at" => Time.current.utc.iso8601),
          created_by_type: created_by_type,
          note: note
        )
      end

      # ── ROLLBACK ───────────────────────────────────────────────────────────
      # Re-apply the manifest from version +version+ so the source's config
      # returns to that snapshot. The PRE-rollback state is captured FIRST as a
      # new "rollback" snapshot (so the rollback itself is reversible/audited),
      # then the historical manifest is replayed through #import (which never
      # touches credentials).
      #
      # @param data_source [Ai::DataSource]
      # @param version [Integer, Ai::DataSourceConfigVersion] version number or
      #   the version record to restore.
      # @return [Hash] {
      #   data_source:, restored_version:, created:, updated_endpoints:, errors:
      # } — or { error: } when the version is not found for this source.
      def rollback!(data_source, version)
        record = resolve_version(data_source, version)
        return { error: "config version not found for this data source" } if record.nil?

        # Capture the CURRENT (pre-rollback) manifest BEFORE replaying, but PERSIST
        # the pre-rollback snapshot ONLY once the replay succeeds — a failed replay
        # must leave no spurious "rollback" version behind. #import is itself
        # transactional and rolls back its own partial writes on error.
        pre_manifest = export(data_source).merge("exported_at" => Time.current.utc.iso8601)

        result = import(record.manifest, slug: data_source.slug, dry_run: false)
        if result[:errors].present? || result[:data_source].nil?
          return {
            data_source: result[:data_source],
            restored_version: nil,
            created: result[:created],
            updated_endpoints: result[:updated_endpoints],
            errors: result[:errors].presence || ["rollback replay failed"]
          }
        end

        # Replay succeeded — record the pre-rollback snapshot for reversibility/audit.
        persist_manifest_snapshot(
          data_source, pre_manifest,
          created_by_type: "rollback",
          note: "pre-rollback state before restoring v#{record.version}"
        )

        {
          data_source: result[:data_source],
          restored_version: record.version,
          created: result[:created],
          updated_endpoints: result[:updated_endpoints],
          errors: []
        }
      end

      private

      attr_reader :account

      # ---- export helpers ----------------------------------------------------

      # Allowlisted, non-secret source attrs + a SANITIZED auth_config.
      def export_source(data_source)
        attrs = SOURCE_EXPORT_KEYS.each_with_object({}) do |key, acc|
          next unless data_source.respond_to?(key)

          # scrub_value recursively drops secret-KEYED entries from the free-form
          # jsonb columns (configuration / default_parameters / metadata) so a secret
          # planted in one of them can never ride the manifest; scalars pass through.
          acc[key] = scrub_value(data_source.public_send(key))
        end
        # auth_config is exported ONLY through the sanitizer — never raw.
        attrs["auth_config"] = sanitize_auth_config(data_source.auth_config)
        attrs
      end

      def export_endpoints(data_source)
        data_source.endpoints.order(:slug).map do |ep|
          ENDPOINT_EXPORT_KEYS.each_with_object({}) do |key, acc|
            next unless ep.respond_to?(key)

            # Same recursive secret-scrub over the endpoint's free-form jsonb
            # (query_template / body_template / response_mapping / metadata / ...).
            acc[key] = scrub_value(ep.public_send(key))
          end
        end
      end

      # Strip auth_config down to NON-secret knobs. Two gates, both must pass:
      #   1. ALLOWLIST — key must be in AUTH_CONFIG_ALLOWED_KEYS.
      #   2. DENYLIST  — key must NOT be flagged secret by #secret_key?.
      # The nested "broker" hash is recursed (its knobs live one level down); any
      # other nested hash/array is recursively scrubbed too, so a secret buried in
      # a nested structure can never leak. Non-Hash input yields {}.
      def sanitize_auth_config(auth_config)
        return {} unless auth_config.is_a?(Hash)

        auth_config.each_with_object({}) do |(raw_key, value), acc|
          key = raw_key.to_s
          next if secret_key?(key)

          if key == "broker" && value.is_a?(Hash)
            cleaned = sanitize_broker(value)
            acc[key] = cleaned unless cleaned.empty?
          elsif AUTH_CONFIG_ALLOWED_KEYS.include?(key)
            acc[key] = scrub_value(value)
          end
          # else: key not allowlisted at the top level -> DROPPED.
        end
      end

      # Sanitize the nested broker hash: allowlist + denylist, same as the top
      # level, recursing into any nested structures defensively.
      def sanitize_broker(broker)
        broker.each_with_object({}) do |(raw_key, value), acc|
          key = raw_key.to_s
          next if secret_key?(key)
          next unless AUTH_CONFIG_ALLOWED_KEYS.include?(key)

          acc[key] = scrub_value(value)
        end
      end

      # Recursively scrub a value so no secret-keyed entry survives inside a
      # nested Hash/Array that rode in under an allowlisted parent key.
      def scrub_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), acc|
            next if secret_key?(k.to_s)

            acc[k.to_s] = scrub_value(v)
          end
        when Array
          value.map { |v| scrub_value(v) }
        else
          value
        end
      end

      # True when a key name looks secret-bearing. Checks the exact-name set
      # first (catches a bare "token"/"key"), then the substring denylist. Used
      # as defense-in-depth ON TOP OF the allowlist.
      def secret_key?(key)
        k = key.to_s.downcase
        return true if SECRET_KEY_EXACT.include?(k)

        SECRET_KEY_SUBSTRINGS.any? { |needle| k.include?(needle) }
      end

      # ---- import helpers ----------------------------------------------------

      # Coerce a manifest (string OR symbol keys, possibly ActionController
      # params) into a plain string-keyed Hash with "source"/"endpoints" present.
      def normalize_manifest(manifest)
        raw = manifest.respond_to?(:to_unsafe_h) ? manifest.to_unsafe_h : manifest
        hash = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
        hash["source"] = {} unless hash["source"].is_a?(Hash)
        hash["endpoints"] = [] unless hash["endpoints"].is_a?(Array)
        hash
      end

      # Re-apply the export allowlist on IMPORT too (never trust an inbound
      # manifest to be clean), and sanitize its auth_config defensively so a
      # hand-edited manifest cannot smuggle a secret into the stored record.
      def sanitized_source_attrs(source)
        src = source.is_a?(Hash) ? source.deep_stringify_keys : {}
        attrs = src.slice(*SOURCE_EXPORT_KEYS)
        attrs["auth_config"] = sanitize_auth_config(src["auth_config"]) if src.key?("auth_config")
        attrs
      end

      # Assign allowlisted attrs to the source, pinning the resolved slug. NEVER
      # assigns account_id from the manifest — the account is fixed to @account.
      # On a CLONE (new record under an override slug), the manifest's name would
      # collide with the source it was exported from (name is unique per account),
      # so de-duplicate it the same way the model de-dupes slugs. Update-in-place
      # (existing record, same slug) keeps its own name — no self-collision.
      def apply_source_attrs(data_source, source_attrs, target_slug, created)
        data_source.account = @account
        source_attrs.each do |key, value|
          next if key == "slug" # pinned explicitly below

          data_source.public_send("#{key}=", value) if data_source.respond_to?("#{key}=")
        end
        data_source.slug = target_slug
        data_source.name = dedup_name(source_attrs["name"]) if created
      end

      # Make a source name unique within the account by appending an incrementing
      # suffix on collision (mirrors Ai::DataSource#generate_slug's de-dup loop).
      # Only used when IMPORT creates a new record, so a clone under a new slug
      # never trips the per-account name-uniqueness validation.
      def dedup_name(name)
        base = name.to_s
        return base unless @account.ai_data_sources.exists?(["lower(name) = ?", base.downcase])

        counter = 2
        loop do
          candidate = "#{base} (#{counter})"
          unless @account.ai_data_sources.exists?(["lower(name) = ?", candidate.downcase])
            return candidate
          end

          counter += 1
        end
      end

      # dry_run: report what WOULD happen without persisting anything.
      def import_preview(data_source, created, endpoints)
        previews = Array(endpoints).map do |raw|
          attrs = sanitized_endpoint_attrs(raw)
          slug = attrs["slug"].to_s
          existing = !created && data_source.persisted? &&
                     data_source.endpoints.exists?(slug: slug)
          { slug: slug, action: existing ? "update" : "create" }
        end

        {
          data_source: data_source,
          created: created,
          updated_endpoints: previews,
          dry_run: true,
          errors: []
        }
      end

      # Persist the source then upsert endpoints, all in one transaction so a
      # partial import never leaves a half-applied source behind.
      def persist_import(data_source, created, endpoints)
        errors = []
        updated_endpoints = []

        ActiveRecord::Base.transaction do
          unless data_source.save
            errors.concat(data_source.errors.full_messages.presence || ["data source could not be saved"])
            raise ActiveRecord::Rollback
          end

          updated_endpoints = upsert_endpoints(data_source, endpoints, errors)
          raise ActiveRecord::Rollback if errors.any?
        end

        {
          data_source: data_source,
          created: created,
          updated_endpoints: updated_endpoints,
          dry_run: false,
          errors: errors
        }
      end

      # Create-or-update each endpoint by slug under the source. A failure on one
      # endpoint records an error (which rolls the whole import back).
      def upsert_endpoints(data_source, endpoints, errors)
        Array(endpoints).filter_map do |raw|
          attrs = sanitized_endpoint_attrs(raw)
          slug = attrs["slug"].to_s
          if slug.blank?
            errors << "endpoint missing slug: #{attrs['name'] || 'unnamed'}"
            next
          end

          endpoint = data_source.endpoints.find_or_initialize_by(slug: slug)
          action = endpoint.new_record? ? "create" : "update"
          attrs.each do |key, value|
            next if key == "slug"

            endpoint.public_send("#{key}=", value) if endpoint.respond_to?("#{key}=")
          end

          if endpoint.save
            { slug: slug, action: action }
          else
            errors << "endpoint #{slug}: #{endpoint.errors.full_messages.join(', ')}"
            nil
          end
        end
      end

      # Allowlist endpoint attrs on import (symmetry with export); inbound
      # manifests are never trusted to be already-clean.
      def sanitized_endpoint_attrs(raw)
        hash = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
        hash.slice(*ENDPOINT_EXPORT_KEYS)
      end

      def import_error(message, dry_run:)
        {
          data_source: nil,
          created: false,
          updated_endpoints: [],
          dry_run: dry_run,
          errors: [message]
        }
      end

      # Resolve a version arg (Integer number OR a record) to the
      # account-scoped DataSourceConfigVersion for this source, or nil.
      def resolve_version(data_source, version)
        return nil unless data_source&.persisted?

        if version.is_a?(Ai::DataSourceConfigVersion)
          return version if version.ai_data_source_id == data_source.id &&
                            version.account_id == @account.id

          return nil
        end

        Ai::DataSourceConfigVersion
          .where(account_id: @account.id)
          .for_data_source(data_source)
          .find_by(version: version.to_i)
      end

      # Persist a config-version snapshot from an ALREADY-BUILT manifest at the next
      # sequential version. next_version_for is a check-then-act (SELECT MAX+1), so a
      # concurrent snapshot can collide on the unique (source, version) index; retry
      # a couple of times (recomputing the next version) rather than failing the call.
      def persist_manifest_snapshot(data_source, manifest, created_by_type:, note: nil)
        attempts = 0
        begin
          Ai::DataSourceConfigVersion.create!(
            data_source: data_source,
            account: @account,
            version: Ai::DataSourceConfigVersion.next_version_for(data_source),
            manifest: manifest,
            created_by_type: created_by_type,
            note: note
          )
        rescue ActiveRecord::RecordNotUnique
          attempts += 1
          retry if attempts < 3

          raise
        end
      end
    end
  end
end
