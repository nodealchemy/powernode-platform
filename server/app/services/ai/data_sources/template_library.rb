# frozen_string_literal: true

module Ai
  module DataSources
    # A curated, ACCOUNT-AGNOSTIC, CREDENTIAL-FREE library of starter data-source
    # manifests — the "config not code" onboarding story made concrete. Each entry
    # is a manifest in the EXACT shape Ai::DataSources::ConfigPortabilityService
    # emits from #export and accepts in #import, so installing a template is just
    # "import this seeded manifest into your account".
    #
    # ── WHAT A TEMPLATE IS ────────────────────────────────────────────────────
    # A template is a STARTING POINT, not a finished, runnable source. Templates
    # are intentionally minimal and obviously NON-secret:
    #   - api_base_url points at a documented PUBLIC endpoint (no private host),
    #   - auth_scheme is "none" or "api_key" (the latter with NO secret material —
    #     just the scheme NAME; the operator attaches the key AFTER install),
    #   - auth_config carries only NON-secret knobs (and is usually {}),
    #   - endpoints describe the retrieval contract (path/method/format/mapping),
    #     never credentials.
    # After installing a template the operator typically (1) attaches a credential
    # via the credentials API/UI when auth is required, and (2) tweaks the base URL
    # / parameters for their specific feed. Installation NEVER sets credentials —
    # that is ConfigPortabilityService#import's contract and it is preserved here.
    #
    # ── SECURITY ──────────────────────────────────────────────────────────────
    # These manifests are checked into the repo and shipped to every account, so
    # they MUST be credential-free by construction. They never contain api keys,
    # secrets, tokens, passwords, or vault handles. Even so, install() routes
    # through ConfigPortabilityService#import, which RE-RUNS the auth_config
    # sanitizer on the way in — a defense-in-depth guarantee that nothing
    # secret-ish could ride a (hand-edited) template into a stored record.
    #
    # ── USAGE ─────────────────────────────────────────────────────────────────
    #   Ai::DataSources::TemplateLibrary.all
    #     #=> [{ slug:, name:, description:, category:, manifest: }, ...]
    #   Ai::DataSources::TemplateLibrary.find("generic-rest-json")
    #     #=> { slug:, name:, description:, category:, manifest: } or nil
    #   Ai::DataSources::TemplateLibrary.install("rss-feed", account: acct)
    #     #=> ConfigPortabilityService#import result Hash (or nil-source error
    #     #   when the slug is unknown)
    #
    # install() accepts the same slug:/dry_run: overrides ConfigPortabilityService
    # exposes, so an operator can preview the materialization or land it under a
    # custom slug (e.g. to install the same template twice).
    module TemplateLibrary
      module_function

      # Build the catalog fresh on each call so a returned manifest can be mutated
      # by a caller without poisoning the next install (the manifests are nested
      # Hashes/Arrays; a frozen constant would force callers to deep-dup anyway).
      #
      # @return [Array<Hash>] each: { slug:, name:, description:, category:, manifest: }
      def all
        [
          generic_rest_json_template,
          rss_feed_template,
          open_meteo_weather_template,
          graphql_template
        ]
      end

      # Look up a single template by its catalog slug.
      #
      # @param slug [String]
      # @return [Hash, nil] the { slug:, name:, description:, category:, manifest: }
      #   entry, or nil when no template has that slug.
      def find(slug)
        target = slug.to_s
        all.find { |tpl| tpl[:slug] == target }
      end

      # Materialize a template into +account+ by importing its manifest through
      # ConfigPortabilityService. NEVER sets credentials (the operator attaches
      # those after install) — that is the import contract, unchanged here.
      #
      # @param slug [String] catalog slug of the template to install.
      # @param account [Account] the account to create the source under.
      # @param target_slug [String, nil] override for the created source's slug
      #   (lets the same template be installed more than once). Defaults to the
      #   template manifest's own source slug.
      # @param dry_run [Boolean] when true, persist NOTHING and return the import
      #   preview of what WOULD be created.
      # @return [Hash] the ConfigPortabilityService#import result
      #   ({ data_source:, created:, updated_endpoints:, dry_run:, errors: }). When
      #   the slug is unknown, returns that same shape with a nil source and an
      #   explanatory error (mirrors import's hard-failure shape).
      def install(slug, account:, target_slug: nil, dry_run: false)
        template = find(slug)
        if template.nil?
          return {
            data_source: nil,
            created: false,
            updated_endpoints: [],
            dry_run: dry_run,
            errors: ["unknown template: #{slug}"]
          }
        end

        ConfigPortabilityService
          .new(account: account)
          .import(template[:manifest], slug: target_slug, dry_run: dry_run)
      end

      # ── TEMPLATE DEFINITIONS ────────────────────────────────────────────────
      # Each builds a { slug:, name:, description:, category:, manifest: } entry
      # whose :manifest matches ConfigPortabilityService's exported shape exactly
      # (manifest_version / source / endpoints / exported_at). exported_at stays
      # nil — these are byte-stable seeds, not point-in-time exports.

      # A blank, auth-free REST/JSON scaffold. The api_base_url is a placeholder
      # the operator replaces with their actual host; one example GET endpoint
      # shows the path-template + response-mapping shape to copy.
      def generic_rest_json_template
        {
          slug: "generic-rest-json",
          name: "Generic REST JSON API",
          description: "Starter scaffold for any REST API that returns JSON. " \
                       "Replace the placeholder base URL with your host and adjust " \
                       "the example endpoint's path, query, and response mapping. " \
                       "Attach a credential afterward only if the API needs auth.",
          category: "general",
          manifest: base_manifest(
            source: {
              "name" => "Generic REST JSON API",
              "slug" => "generic-rest-json",
              "source_type" => "custom",
              "category" => "general",
              "protocol" => "rest",
              "api_base_url" => "https://api.example.com",
              "description" => "Replace this base URL and the example endpoint " \
                               "with your REST/JSON API's details.",
              "documentation_url" => nil,
              "requires_auth" => false,
              "auth_scheme" => "none",
              "configuration" => { "default_headers" => { "Accept" => "application/json" } },
              "default_parameters" => {},
              "metadata" => { "template" => "generic-rest-json", "starter" => true }
            },
            endpoints: [
              {
                "name" => "Example resource",
                "slug" => "example-resource",
                "http_method" => "GET",
                "path_template" => "/v1/resource",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "query_template" => { "limit" => "{limit}" },
                "response_mapping" => { "records_path" => "data" },
                "metadata" => { "note" => "Edit path_template/query_template/response_mapping for your API." }
              }
            ]
          )
        }
      end

      # A public RSS/Atom feed reader. RSS is XML and almost always public, so
      # auth_scheme is "none". The base URL is a placeholder feed host; the single
      # endpoint pulls the feed root and maps items out of the channel.
      def rss_feed_template
        {
          slug: "rss-feed",
          name: "RSS / Atom Feed",
          description: "Starter for a public RSS or Atom feed. Point the base URL " \
                       "at the feed's host and the endpoint path at the feed file. " \
                       "No credential needed for public feeds.",
          category: "news",
          manifest: base_manifest(
            source: {
              "name" => "RSS / Atom Feed",
              "slug" => "rss-feed",
              "source_type" => "custom",
              "category" => "news",
              "protocol" => "rest",
              "api_base_url" => "https://example.com",
              "description" => "Replace the base URL and feed path with your public feed.",
              "documentation_url" => nil,
              "requires_auth" => false,
              "auth_scheme" => "none",
              "respect_robots" => true,
              "crawl_delay_seconds" => 5,
              "configuration" => { "default_headers" => { "Accept" => "application/rss+xml" } },
              "metadata" => { "template" => "rss-feed", "starter" => true }
            },
            endpoints: [
              {
                "name" => "Feed",
                "slug" => "feed",
                "http_method" => "GET",
                "path_template" => "/feed.xml",
                "response_format" => "rss",
                "expected_content_type" => "application/rss+xml",
                "change_detection" => "etag",
                "monitorable" => true,
                "cache_ttl_seconds" => 900,
                "response_mapping" => { "record_node" => "item" },
                "metadata" => { "note" => "Set path_template to your feed's path (e.g. /rss, /atom.xml)." }
              }
            ]
          )
        }
      end

      # Open-Meteo — a genuinely public, key-free open-data weather API. This is a
      # working example (the base URL and endpoint are real and need no auth), so
      # it doubles as a "this actually runs out of the box" template.
      def open_meteo_weather_template
        {
          slug: "open-meteo-weather",
          name: "Open-Meteo Weather (public, no key)",
          description: "Public open-data weather API that requires NO API key. " \
                       "Works out of the box: pass latitude/longitude params to the " \
                       "forecast endpoint. A good reference for the manifest shape.",
          category: "weather",
          manifest: base_manifest(
            source: {
              "name" => "Open-Meteo Weather",
              "slug" => "open-meteo-weather",
              "source_type" => "open_meteo",
              "category" => "weather",
              "protocol" => "rest",
              "api_base_url" => "https://api.open-meteo.com",
              "description" => "Free public weather forecasts — no authentication required.",
              "documentation_url" => "https://open-meteo.com/en/docs",
              "requires_auth" => false,
              "auth_scheme" => "none",
              "respect_robots" => true,
              "rate_limits" => { "requests_per_minute" => 60 },
              "configuration" => { "default_headers" => { "Accept" => "application/json" } },
              "default_parameters" => { "timezone" => "UTC" },
              "metadata" => { "template" => "open-meteo-weather", "starter" => true, "public" => true }
            },
            endpoints: [
              {
                "name" => "Forecast",
                "slug" => "forecast",
                "http_method" => "GET",
                "path_template" => "/v1/forecast",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "cache_ttl_seconds" => 600,
                "query_template" => {
                  "latitude" => "{latitude}",
                  "longitude" => "{longitude}",
                  "current" => "temperature_2m,wind_speed_10m"
                },
                "response_mapping" => { "records_path" => "current" },
                "metadata" => { "note" => "Provide latitude/longitude params at query time." }
              }
            ]
          )
        }
      end

      # A generic GraphQL scaffold. GraphQL is a single POST endpoint carrying a
      # query in the body; auth_scheme is "api_key" to show the COMMON case, but
      # NO key material is present — the operator attaches the credential after
      # install. auth_config stays {} (no non-secret knobs needed for a bare key).
      def graphql_template
        {
          slug: "generic-graphql",
          name: "Generic GraphQL API",
          description: "Starter for a GraphQL API (single POST endpoint, query in " \
                       "the body). Set the base URL and edit the example query. " \
                       "auth_scheme is 'api_key' as a hint — attach the actual key " \
                       "as a credential after installing; none is shipped here.",
          category: "general",
          manifest: base_manifest(
            source: {
              "name" => "Generic GraphQL API",
              "slug" => "generic-graphql",
              "source_type" => "custom",
              "category" => "general",
              "protocol" => "graphql",
              "api_base_url" => "https://api.example.com",
              "description" => "Replace the base URL and the example query for your GraphQL endpoint.",
              "documentation_url" => nil,
              "requires_auth" => true,
              "auth_scheme" => "api_key",
              "auth_config" => {}, # NON-secret knobs only; the key is a credential, not here.
              "configuration" => { "default_headers" => { "Content-Type" => "application/json" } },
              "metadata" => { "template" => "generic-graphql", "starter" => true }
            },
            endpoints: [
              {
                "name" => "GraphQL query",
                "slug" => "graphql",
                "http_method" => "POST",
                "path_template" => "/graphql",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "body_template" => {
                  "query" => "query { viewer { id } }",
                  "variables" => {}
                },
                "response_mapping" => { "records_path" => "data" },
                "metadata" => { "note" => "Replace the body query/variables with your GraphQL operation." }
              }
            ]
          )
        }
      end

      # Wrap a source/endpoints pair in the canonical manifest envelope so every
      # template matches ConfigPortabilityService's exported shape exactly. The
      # source defaults below mirror the model's column defaults for keys a sparse
      # template omits, keeping installed sources predictable. exported_at is nil
      # (these are seeds, not exports); ConfigPortabilityService stamps it only
      # when it snapshots a live source.
      def base_manifest(source:, endpoints:)
        {
          "manifest_version" => ConfigPortabilityService::MANIFEST_VERSION,
          "source" => default_source.merge(source),
          "endpoints" => endpoints,
          "exported_at" => nil
        }
      end

      # Non-secret source defaults applied under every template (overridden by the
      # template's own values). Mirrors Ai::DataSource's safe defaults so an
      # installed source behaves predictably; carries NO auth/secret material.
      def default_source
        {
          "is_active" => true,
          "requires_auth" => false,
          "respect_robots" => true,
          "crawl_delay_seconds" => 0,
          "priority_order" => 100,
          "capabilities" => [],
          "configuration" => {},
          "rate_limits" => {},
          "default_parameters" => {},
          "metadata" => {},
          "auth_scheme" => "none",
          "auth_config" => {}
        }
      end
    end
  end
end
