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
          graphql_template,
          x_com_template,
          linkedin_template,
          reddit_template,
          youtube_template
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

      # X.com (Twitter) API v2 — an OAuth 2.0 Authorization-Code + PKCE (x-com-
      # provider campaign, I1-I3) source with both READ and WRITE endpoints.
      # requires_auth is true and auth_scheme is "bearer" (a hint AND the real
      # signing scheme, since the credential brokered below always yields a
      # bearer token), but — same guarantee as every other template — NO
      # credential material ships here. The operator (1) attaches an
      # Ai::DataSourceCredential carrying client_id/client_secret, (2) runs the
      # authorize/callback flow to populate access_token/refresh_token.
      #
      # auth_config wires the oauth2_authorization_code broker (I3) via the
      # standard data_source.auth_config["broker"]["type"] mechanism
      # (Ai::DataSources::QueryService#broker_config ->
      # Ai::DataSources::Credentials::Registry.for) so every signed fetch
      # silently refreshes a near-expiry access_token before dispatch. token_url
      # is deliberately duplicated at the top level AND under "broker": I1's
      # OauthAuthorizationCodeService#exchange_code_for_token reads the
      # TOP-LEVEL auth_config["token_url"], while I3's
      # Oauth2AuthorizationCodeBroker reads auth_config["broker"]["token_url"] —
      # two different readers, same real endpoint, so the value must appear at
      # both keys. "scope" (singular, a space-joined String) is used rather than
      # "scopes" (an Array) because OauthAuthorizationCodeService#requested_scopes
      # accepts either spelling but ConfigPortabilityService's auth_config
      # allowlist only admits the singular key.
      #
      # The "Create Post" endpoint is a genuine SIDE-EFFECTING write (POST
      # /2/tweets): cache_ttl_seconds is 0 and metadata carries
      # side_effecting: true so operators/agents can see it is not a passive
      # read. QueryService itself refuses to cache or dedupe ANY non-GET/HEAD
      # request (or one with cache_ttl_seconds <= 0) regardless of this
      # metadata flag — see QueryService#cacheable_request? — so a retried post
      # always really posts rather than silently replaying a cached response.
      def x_com_template
        {
          slug: "x-com",
          name: "X.com",
          description: "X (Twitter) API v2 — OAuth 2.0 Authorization Code + PKCE. " \
                       "Read recent posts/timelines and publish new posts. Attach an " \
                       "OAuth2 app credential (client_id/client_secret) after install, " \
                       "then run the connect flow to authorize — no tokens are shipped here.",
          category: "social",
          manifest: base_manifest(
            source: {
              "name" => "X.com",
              "slug" => "x-com",
              "source_type" => "x_com",
              "category" => "social",
              "protocol" => "rest",
              "api_base_url" => "https://api.twitter.com",
              "description" => "X (Twitter) API v2 — connect an OAuth2 app and authorize " \
                               "to read posts and publish new ones.",
              "documentation_url" => "https://developer.twitter.com/en/docs/twitter-api",
              "requires_auth" => true,
              # An authenticated REST API, not a crawled resource — robots.txt
              # governs page crawling, not signed API calls, so this overrides
              # default_source's respect_robots:true (correct for the RSS/weather
              # templates, wrong here — it would fetch/honor api.twitter.com's
              # robots.txt before every signed request).
              "respect_robots" => false,
              "auth_scheme" => "bearer",
              "auth_config" => {
                "authorize_url" => "https://twitter.com/i/oauth2/authorize",
                "token_url" => "https://api.twitter.com/2/oauth2/token",
                "scope" => "tweet.read tweet.write users.read offline.access",
                "broker" => {
                  "type" => "oauth2_authorization_code",
                  "token_url" => "https://api.twitter.com/2/oauth2/token"
                }
              },
              "configuration" => { "default_headers" => { "Accept" => "application/json" } },
              "metadata" => { "template" => "x-com", "starter" => true }
            },
            endpoints: [
              {
                "name" => "Recent search",
                "slug" => "recent-search",
                "http_method" => "GET",
                "path_template" => "/2/tweets/search/recent",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "query_template" => { "query" => "{query}" },
                "response_mapping" => { "records_path" => "data" },
                "metadata" => { "note" => "query is a required X.com search operator string." }
              },
              {
                "name" => "User tweets",
                "slug" => "user-tweets",
                "http_method" => "GET",
                "path_template" => "/2/users/{id}/tweets",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "response_mapping" => { "records_path" => "data" },
                "metadata" => { "note" => "id is the X.com numeric user id (path param)." }
              },
              {
                "name" => "Create post",
                "slug" => "create-post",
                "http_method" => "POST",
                "path_template" => "/2/tweets",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "cache_ttl_seconds" => 0,
                "body_template" => { "text" => "{text}" },
                "response_mapping" => { "records_path" => "data" },
                "metadata" => {
                  "note" => "SIDE-EFFECTING write — publishes a real post. Never cached.",
                  "side_effecting" => true
                }
              }
            ]
          )
        }
      end

      # LinkedIn — provider-wave-2 (W1), the SAME OAuth 2.0 Authorization-Code
      # seam as x_com_template above (oauth2_authorization_code broker,
      # BearerSigner, write-safety, approval-gating): zero new signer/code, only
      # a manifest. requires_auth/auth_scheme mirror x-com exactly.
      #
      # Scopes: LinkedIn's self-serve "Sign In with LinkedIn using OpenID
      # Connect" + "Share on LinkedIn" products grant "openid profile email
      # w_member_social" without partner review; a read-your-own-posts scope
      # (e.g. r_member_social) exists but is gated behind LinkedIn's Marketing
      # Developer Platform partner program, so it is deliberately NOT requested
      # here — the read endpoint below uses the OpenID userinfo endpoint
      # instead, which is reachable with the self-serve scopes alone.
      #
      # Posts API note: a successful "Create post" (POST /rest/posts) returns
      # 201 with the created post's URN in the "x-restli-id" response HEADER,
      # not the JSON body (which LinkedIn documents as typically empty) — the
      # response_mapping below is a best-effort hint for APIs/test doubles that
      # do echo a body; the header is outside this generic JSON-body pipeline.
      def linkedin_template
        {
          slug: "linkedin",
          name: "LinkedIn",
          description: "LinkedIn API — OAuth 2.0 Authorization Code. Read your " \
                       "profile and publish posts. Attach an OAuth2 app credential " \
                       "(client_id/client_secret) after install, then run the " \
                       "connect flow to authorize — no tokens are shipped here.",
          category: "social",
          manifest: base_manifest(
            source: {
              "name" => "LinkedIn",
              "slug" => "linkedin",
              "source_type" => "linkedin",
              "category" => "social",
              "protocol" => "rest",
              "api_base_url" => "https://api.linkedin.com",
              "description" => "LinkedIn API — connect an OAuth2 app and authorize " \
                               "to read your profile and publish new posts.",
              "documentation_url" => "https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api",
              "requires_auth" => true,
              # Authenticated REST API, not a crawled resource — same rationale
              # as x-com's override.
              "respect_robots" => false,
              "auth_scheme" => "bearer",
              "auth_config" => {
                "authorize_url" => "https://www.linkedin.com/oauth/v2/authorization",
                "token_url" => "https://www.linkedin.com/oauth/v2/accessToken",
                "scope" => "openid profile email w_member_social",
                "broker" => {
                  "type" => "oauth2_authorization_code",
                  "token_url" => "https://www.linkedin.com/oauth/v2/accessToken"
                }
              },
              "configuration" => {
                "default_headers" => {
                  "Accept" => "application/json",
                  "LinkedIn-Version" => "202401",
                  "X-Restli-Protocol-Version" => "2.0.0"
                }
              },
              "metadata" => { "template" => "linkedin", "starter" => true }
            },
            endpoints: [
              {
                "name" => "Profile",
                "slug" => "profile",
                "http_method" => "GET",
                "path_template" => "/v2/userinfo",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "response_mapping" => {},
                "metadata" => { "note" => "OpenID Connect userinfo — a flat object, wrapped as a single record." }
              },
              {
                "name" => "Create post",
                "slug" => "create-post",
                "http_method" => "POST",
                "path_template" => "/rest/posts",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "cache_ttl_seconds" => 0,
                "body_template" => {
                  "author" => "urn:li:person:{person_id}",
                  "commentary" => "{text}",
                  "visibility" => "PUBLIC",
                  "distribution" => {
                    "feedDistribution" => "MAIN_FEED",
                    "targetEntities" => [],
                    "thirdPartyDistributionChannels" => []
                  },
                  "lifecycleState" => "PUBLISHED",
                  "isReshareDisabledByAuthor" => false
                },
                "response_mapping" => { "records_path" => "data" },
                "metadata" => {
                  "note" => "SIDE-EFFECTING write — publishes a real post. Never cached. " \
                            "person_id is the LinkedIn member URN id (path/body param).",
                  "side_effecting" => true
                }
              }
            ]
          )
        }
      end

      # Reddit — provider-wave-2 (W1), same OAuth2 Authorization-Code seam.
      #
      # Reddit's API rules REQUIRE a unique, descriptive User-Agent on every
      # call (generic/library user-agents are aggressively rate-limited) — the
      # placeholder below MUST be customized by the operator after install.
      # Authenticated calls go to oauth.reddit.com, never www.reddit.com.
      def reddit_template
        {
          slug: "reddit",
          name: "Reddit",
          description: "Reddit API — OAuth 2.0 Authorization Code. Read subreddit " \
                       "listings and submit posts. Attach an OAuth2 app credential " \
                       "(client_id/client_secret) after install, then run the " \
                       "connect flow to authorize — no tokens are shipped here. " \
                       "Customize the User-Agent header after install (Reddit " \
                       "requires a unique, descriptive one per its API rules).",
          category: "social",
          manifest: base_manifest(
            source: {
              "name" => "Reddit",
              "slug" => "reddit",
              "source_type" => "reddit",
              "category" => "social",
              "protocol" => "rest",
              "api_base_url" => "https://oauth.reddit.com",
              "description" => "Reddit API — connect an OAuth2 app and authorize " \
                               "to read subreddit listings and submit posts.",
              "documentation_url" => "https://www.reddit.com/dev/api/oauth",
              "requires_auth" => true,
              "respect_robots" => false,
              "auth_scheme" => "bearer",
              "auth_config" => {
                "authorize_url" => "https://www.reddit.com/api/v1/authorize",
                "token_url" => "https://www.reddit.com/api/v1/access_token",
                "scope" => "read submit identity",
                "broker" => {
                  "type" => "oauth2_authorization_code",
                  "token_url" => "https://www.reddit.com/api/v1/access_token"
                }
              },
              "configuration" => {
                "default_headers" => {
                  "Accept" => "application/json",
                  "User-Agent" => "powernode-data-source/1.0 (by /u/change-me)"
                }
              },
              "metadata" => { "template" => "reddit", "starter" => true }
            },
            endpoints: [
              {
                "name" => "Subreddit new posts",
                "slug" => "subreddit-new",
                "http_method" => "GET",
                "path_template" => "/r/{subreddit}/new",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "query_template" => { "limit" => "{limit}" },
                "response_mapping" => { "records_path" => "data.children" },
                "metadata" => {
                  "note" => "Each record is a Reddit \"Listing\" child ({kind, data}); " \
                            "post fields live one level deeper, under record[\"data\"]."
                }
              },
              {
                "name" => "Submit post",
                "slug" => "submit-post",
                "http_method" => "POST",
                "path_template" => "/api/submit",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "cache_ttl_seconds" => 0,
                "body_template" => {
                  "sr" => "{subreddit}",
                  "kind" => "self",
                  "title" => "{title}",
                  "text" => "{text}",
                  "api_type" => "json"
                },
                "response_mapping" => { "records_path" => "json.data" },
                "metadata" => {
                  "note" => "SIDE-EFFECTING write — submits a real post. Never cached.",
                  "side_effecting" => true
                }
              }
            ]
          )
        }
      end

      # YouTube (Google OAuth 2.0) — provider-wave-2 (W1), same generic
      # Authorization-Code seam; Google is just another provider on it.
      #
      # READ-ONLY for W1: publishing to YouTube is a video upload (resumable,
      # multipart — a materially different request shape than every other
      # endpoint in this library, which are single-request JSON/form calls).
      # Scope is deliberately limited to youtube.readonly (least privilege —
      # an unused upload scope would need Google's app-verification review for
      # no benefit yet). A future increment can add an upload endpoint once the
      # adapter layer supports resumable/multipart bodies.
      #
      # Note: Google typically requires "access_type=offline&prompt=consent" on
      # the authorize request to guarantee a refresh_token on RE-authorization;
      # OauthAuthorizationCodeService#build_authorize_request sends a fixed
      # query set (client_id/redirect_uri/response_type/scope/state/PKCE) with
      # no per-provider extra-params hook, so a first-time consent should still
      # return a refresh_token, but a repeat authorization may not. Flagged for
      # the connect-flow owner rather than worked around here (config-only).
      def youtube_template
        {
          slug: "youtube",
          name: "YouTube",
          description: "YouTube Data API v3 — OAuth 2.0 Authorization Code. " \
                       "Search videos (read-only for now). Attach an OAuth2 app " \
                       "credential (client_id/client_secret) after install, then " \
                       "run the connect flow to authorize — no tokens are shipped " \
                       "here. Publishing (video upload) is not yet supported.",
          category: "social",
          manifest: base_manifest(
            source: {
              "name" => "YouTube",
              "slug" => "youtube",
              "source_type" => "youtube",
              "category" => "social",
              "protocol" => "rest",
              "api_base_url" => "https://www.googleapis.com/youtube/v3",
              "description" => "YouTube Data API v3 — connect a Google OAuth2 app " \
                               "and authorize to search videos.",
              "documentation_url" => "https://developers.google.com/youtube/v3/docs",
              "requires_auth" => true,
              "respect_robots" => false,
              "auth_scheme" => "bearer",
              "auth_config" => {
                "authorize_url" => "https://accounts.google.com/o/oauth2/v2/auth",
                "token_url" => "https://oauth2.googleapis.com/token",
                "scope" => "https://www.googleapis.com/auth/youtube.readonly",
                "broker" => {
                  "type" => "oauth2_authorization_code",
                  "token_url" => "https://oauth2.googleapis.com/token"
                }
              },
              "configuration" => { "default_headers" => { "Accept" => "application/json" } },
              "metadata" => {
                "template" => "youtube", "starter" => true,
                "publish" => "deferred — video upload needs resumable/multipart support, out of scope for W1"
              }
            },
            endpoints: [
              {
                "name" => "Search videos",
                "slug" => "search-videos",
                "http_method" => "GET",
                "path_template" => "/search",
                "response_format" => "json",
                "expected_content_type" => "application/json",
                "query_template" => {
                  "part" => "snippet",
                  "q" => "{query}",
                  "type" => "video",
                  "maxResults" => "{max_results}"
                },
                "response_mapping" => { "records_path" => "items" },
                "metadata" => { "note" => "q is a YouTube search query string." }
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
