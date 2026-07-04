# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::TemplateLibrary is the "config not code" onboarding catalog:
# a curated set of ACCOUNT-AGNOSTIC, CREDENTIAL-FREE starter data-source
# manifests, each in the EXACT shape ConfigPortabilityService#export emits and
# #import accepts. Installing a template is just "import this seeded manifest".
#
# These specs guard the two properties that make the library safe to ship to
# every account:
#   1. Every templated manifest is CREDENTIAL-FREE by construction (no api
#      keys/secrets/tokens/passwords anywhere; auth_scheme is a NAME only).
#   2. .install materializes a real source through ConfigPortabilityService and
#      NEVER sets credentials (the operator attaches those after install).
#
# .install persists a real Ai::DataSource, whose after_commit fires a
# knowledge-graph re-sync (Ai::DataSourceGraph::BridgeService#sync_data_source).
# We stub that one method so persistence under DatabaseCleaner :deletion never
# reaches Redis/embeddings — matching the sibling data-source service specs.
RSpec.describe Ai::DataSources::TemplateLibrary, type: :service do
  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService)
      .to receive(:sync_data_source)
  end

  let(:account) { create(:account) }

  # ── Recursive secret-scanner ──────────────────────────────────────────────
  # Walk an arbitrary nested Hash/Array manifest and collect every string KEY
  # that looks secret-bearing (matches ConfigPortabilityService's own denylist),
  # so we can assert no template ever carries one. Mirrors the service's
  # SECRET_KEY_EXACT + SECRET_KEY_SUBSTRINGS gates. Kept as method-local frozen
  # arrays (not top-level constants) so nothing leaks into the global namespace.
  def secret_keyish?(key)
    exact = %w[token key apikey api_key auth jwt bearer signature passphrase].freeze
    substrings = %w[
      secret password passwd credential private mnemonic seed_phrase
      access_key secret_key client_secret api_secret web_identity_token
    ].freeze

    k = key.to_s.downcase
    return true if exact.include?(k)

    substrings.any? { |needle| k.include?(needle) }
  end

  # Collect every offending key path in a nested structure (empty == clean).
  def secret_key_paths(value, prefix = "")
    case value
    when Hash
      value.flat_map do |k, v|
        path = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
        offenders = secret_keyish?(k) ? [path] : []
        offenders + secret_key_paths(v, path)
      end
    when Array
      value.each_with_index.flat_map { |v, i| secret_key_paths(v, "#{prefix}[#{i}]") }
    else
      []
    end
  end

  # Collect every leaf STRING value in a nested structure, so we can scan the
  # actual data for secret-shaped material (long keys, "Bearer ..." headers).
  def leaf_strings(value)
    case value
    when Hash  then value.values.flat_map { |v| leaf_strings(v) }
    when Array then value.flat_map { |v| leaf_strings(v) }
    when String then [value]
    else []
    end
  end

  describe ".all" do
    subject(:templates) { described_class.all }

    it "returns the seeded templates" do
      expect(templates).to be_an(Array)
      expect(templates).not_to be_empty
    end

    it "exposes the catalog slugs" do
      expect(templates.map { |t| t[:slug] }).to contain_exactly(
        "generic-rest-json",
        "rss-feed",
        "open-meteo-weather",
        "generic-graphql",
        "x-com",
        "linkedin",
        "reddit",
        "youtube",
        "mastodon",
        "bluesky"
      )
    end

    it "gives every entry slug/name/description/category/manifest" do
      templates.each do |tpl|
        expect(tpl[:slug]).to be_present, "template missing slug: #{tpl.inspect}"
        expect(tpl[:name]).to be_present, "template #{tpl[:slug]} missing name"
        expect(tpl[:description]).to be_present, "template #{tpl[:slug]} missing description"
        expect(tpl[:category]).to be_present, "template #{tpl[:slug]} missing category"
        expect(tpl[:manifest]).to be_a(Hash), "template #{tpl[:slug]} missing manifest"
      end
    end

    it "has unique slugs across the catalog" do
      slugs = templates.map { |t| t[:slug] }
      expect(slugs.uniq).to eq(slugs)
    end

    describe "each manifest is in the export/import shape" do
      it "carries manifest_version / source / endpoints" do
        templates.each do |tpl|
          manifest = tpl[:manifest]
          expect(manifest["manifest_version"])
            .to eq(Ai::DataSources::ConfigPortabilityService::MANIFEST_VERSION),
                "template #{tpl[:slug]} has wrong manifest_version"
          expect(manifest["source"]).to be_a(Hash), "template #{tpl[:slug]} source not a Hash"
          expect(manifest["endpoints"]).to be_an(Array), "template #{tpl[:slug]} endpoints not an Array"
          expect(manifest["endpoints"]).not_to be_empty, "template #{tpl[:slug]} has no endpoints"
        end
      end

      it "uses string keys throughout the manifest (export emits string keys)" do
        templates.each do |tpl|
          manifest = tpl[:manifest]
          expect(manifest.keys).to all(be_a(String)), "template #{tpl[:slug]} manifest has non-string keys"
          expect(manifest["source"].keys).to all(be_a(String)), "template #{tpl[:slug]} source has non-string keys"
          manifest["endpoints"].each do |ep|
            expect(ep.keys).to all(be_a(String)), "template #{tpl[:slug]} endpoint has non-string keys"
          end
        end
      end

      it "gives every source a slug and name (import keys on slug)" do
        templates.each do |tpl|
          source = tpl[:manifest]["source"]
          expect(source["slug"]).to be_present, "template #{tpl[:slug]} source missing slug"
          expect(source["name"]).to be_present, "template #{tpl[:slug]} source missing name"
        end
      end

      it "gives every endpoint a slug (upsert keys on slug)" do
        templates.each do |tpl|
          tpl[:manifest]["endpoints"].each do |ep|
            expect(ep["slug"]).to be_present,
                                  "template #{tpl[:slug]} has an endpoint missing slug: #{ep.inspect}"
          end
        end
      end

      it "leaves exported_at nil (byte-stable seeds, not point-in-time exports)" do
        templates.each do |tpl|
          expect(tpl[:manifest]["exported_at"]).to be_nil,
                                                   "template #{tpl[:slug]} should not stamp exported_at"
        end
      end
    end

    describe "each manifest is CREDENTIAL-FREE (deep scan)" do
      it "has no secret-bearing KEY anywhere in any manifest" do
        templates.each do |tpl|
          offenders = secret_key_paths(tpl[:manifest])
          expect(offenders).to be_empty,
                               "template #{tpl[:slug]} carries secret-bearing keys: #{offenders.inspect}"
        end
      end

      it "carries no secret-shaped leaf VALUE (no Bearer/long-token strings)" do
        templates.each do |tpl|
          strings = leaf_strings(tpl[:manifest])
          bearer_like = strings.select { |s| s =~ /\bBearer\s+\S+/i }
          expect(bearer_like).to be_empty,
                                 "template #{tpl[:slug]} carries a Bearer token value: #{bearer_like.inspect}"

          # No opaque high-entropy-looking secret blobs (>=24 contiguous
          # base64/hex-ish chars). Real template values are URLs, JSONPaths,
          # short words, or templated {{vars}} — with one legitimate exception:
          # a broker "type" selector (e.g. "oauth2_authorization_code", used by
          # the x-com template's auth_config["broker"]["type"]) is a small,
          # fixed, PUBLIC enum straight out of
          # Ai::DataSources::Credentials::Registry::BROKERS — never secret —
          # that can coincidentally read as a 24+-char lowercase/underscore
          # "blob" to this heuristic. Excluded by EXACT value match only (not a
          # regex relaxation), so an actual secret landing under any key still
          # trips this check.
          known_enum_values = Ai::DataSources::Credentials::Registry.types
          blobby = strings.select { |s| s =~ /\A[A-Za-z0-9_\-+\/=]{24,}\z/ } - known_enum_values
          expect(blobby).to be_empty,
                            "template #{tpl[:slug]} carries a secret-shaped blob: #{blobby.inspect}"
        end
      end

      it "exposes auth_scheme as a NAME only (never bundles key material)" do
        templates.each do |tpl|
          source = tpl[:manifest]["source"]
          expect(source["auth_scheme"]).to be_a(String), "template #{tpl[:slug]} auth_scheme not a String"
          # auth_config (when present) is structural knobs only — never secrets.
          if source.key?("auth_config")
            offenders = secret_key_paths(source["auth_config"])
            expect(offenders).to be_empty,
                                 "template #{tpl[:slug]} auth_config carries secret keys: #{offenders.inspect}"
          end
        end
      end

      it "ships the api_key template with an EMPTY auth_config and no key material" do
        graphql = described_class.find("generic-graphql")
        source = graphql[:manifest]["source"]
        expect(source["auth_scheme"]).to eq("api_key")
        expect(source["requires_auth"]).to be(true)
        # The scheme is a hint; the key is attached AFTER install, never shipped.
        expect(source["auth_config"]).to eq({})
      end
    end

    describe "fresh copies on every call (no cross-call poisoning)" do
      it "returns a distinct object graph each call" do
        first = described_class.all
        second = described_class.all
        expect(first).not_to equal(second)
        expect(first.first[:manifest]).not_to equal(second.first[:manifest])
      end

      it "does not let mutating one return value poison the next call" do
        # Aggressively mutate the FIRST call's nested manifest...
        poisoned = described_class.all
        target = poisoned.find { |t| t[:slug] == "generic-rest-json" }
        target[:manifest]["source"]["api_base_url"] = "https://EVIL.example.com"
        target[:manifest]["source"]["api_key"] = "leaked-secret"
        target[:manifest]["endpoints"] << { "slug" => "injected", "name" => "Injected" }

        # ...the NEXT call must be pristine.
        fresh = described_class.all
        fresh_target = fresh.find { |t| t[:slug] == "generic-rest-json" }
        expect(fresh_target[:manifest]["source"]["api_base_url"]).to eq("https://api.example.com")
        expect(fresh_target[:manifest]["source"]).not_to have_key("api_key")
        expect(fresh_target[:manifest]["endpoints"].map { |e| e["slug"] }).not_to include("injected")
      end
    end
  end

  # ── Runtime alignment ─────────────────────────────────────────────────────
  # The templates must speak the SAME dialect the runtime decoders/adapters
  # parse: single-brace {placeholders} (RestAdapter), and response_mapping keys
  # the decoders actually read (records_path for JSON, record_node for XML). A
  # template that ships $.-style JSONPath values or {{double-brace}} placeholders
  # is silently inert. We install each template and exercise the REAL adapter +
  # decoder against the persisted endpoint, exactly as the query pipeline does.
  describe "runtime alignment (placeholders + response_mapping)" do
    def install_endpoint(slug, endpoint_slug)
      result = described_class.install(slug, account: account)
      expect(result[:errors]).to be_empty
      result[:data_source].endpoints.find_by!(slug: endpoint_slug)
    end

    it "renders open-meteo query placeholders with the raw param value (single-brace)" do
      endpoint = install_endpoint("open-meteo-weather", "forecast")

      req = Ai::DataSources::Adapters::RestAdapter.new.build_request(
        endpoint: endpoint, params: { "latitude" => 52, "longitude" => 13 }
      )

      # A correctly single-braced "{latitude}" yields the raw typed param (52),
      # not the mangled "{52}" a "{{latitude}}" template produces.
      expect(req[:query]["latitude"]).to eq(52)
      expect(req[:query]["longitude"]).to eq(13)
    end

    it "renders generic-rest-json's limit placeholder with the raw param" do
      endpoint = install_endpoint("generic-rest-json", "example-resource")

      req = Ai::DataSources::Adapters::RestAdapter.new.build_request(
        endpoint: endpoint, params: { "limit" => 25 }
      )

      expect(req[:query]["limit"]).to eq(25)
    end

    it "extracts open-meteo's records via response_mapping rather than wrapping the whole doc" do
      endpoint = install_endpoint("open-meteo-weather", "forecast")
      body = '{"latitude":52,"current":{"temperature_2m":18.3,"wind_speed_10m":4.1}}'

      records = Ai::DataSources::Decoders::Json.new.decode(body, endpoint: endpoint)

      # The mapping must select the "current" object as the record set; a whole-
      # doc fallback would instead return the top-level hash (with latitude).
      expect(records).to eq([{ "temperature_2m" => 18.3, "wind_speed_10m" => 4.1 }])
    end

    it "extracts generic-rest-json's records via response_mapping" do
      endpoint = install_endpoint("generic-rest-json", "example-resource")
      body = '{"data":[{"id":1},{"id":2}]}'

      records = Ai::DataSources::Decoders::Json.new.decode(body, endpoint: endpoint)

      expect(records).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "locates rss-feed items via the XML decoder's record_node" do
      endpoint = install_endpoint("rss-feed", "feed")
      body = <<~XML
        <rss><channel>
          <item><title>One</title></item>
          <item><title>Two</title></item>
        </channel></rss>
      XML

      records = Ai::DataSources::Decoders::Xml.new.decode(body, endpoint: endpoint)

      expect(records.map { |r| r["title"] }).to eq(%w[One Two])
    end
  end

  describe ".find" do
    it "returns the matching catalog entry for a known slug" do
      tpl = described_class.find("open-meteo-weather")
      expect(tpl).to be_a(Hash)
      expect(tpl[:slug]).to eq("open-meteo-weather")
      expect(tpl[:manifest]["source"]["slug"]).to eq("open-meteo-weather")
    end

    it "accepts a symbol slug (coerced to string)" do
      tpl = described_class.find(:"rss-feed")
      expect(tpl).to be_a(Hash)
      expect(tpl[:slug]).to eq("rss-feed")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.find("does-not-exist")).to be_nil
    end

    it "returns a fresh copy (mutating it does not poison a later find)" do
      described_class.find("rss-feed")[:manifest]["source"]["api_base_url"] = "https://EVIL"
      expect(described_class.find("rss-feed")[:manifest]["source"]["api_base_url"])
        .to eq("https://example.com")
    end
  end

  describe ".install" do
    context "with a known slug" do
      it "materializes a real source via ConfigPortabilityService" do
        result = described_class.install("open-meteo-weather", account: account)

        expect(result[:errors]).to be_empty
        expect(result[:created]).to be(true)
        expect(result[:dry_run]).to be(false)

        source = result[:data_source]
        expect(source).to be_a(Ai::DataSource)
        expect(source).to be_persisted
        expect(source.account_id).to eq(account.id)
        expect(source.slug).to eq("open-meteo-weather")
        expect(source.source_type).to eq("open_meteo")
      end

      it "scopes the installed source to the given account" do
        described_class.install("open-meteo-weather", account: account)
        expect(account.ai_data_sources.where(slug: "open-meteo-weather")).to exist
      end

      it "creates the manifest's endpoints under the source" do
        result = described_class.install("open-meteo-weather", account: account)

        expect(result[:updated_endpoints].map { |e| e[:slug] }).to contain_exactly("forecast")
        expect(result[:updated_endpoints].map { |e| e[:action] }).to all(eq("create"))
        expect(result[:data_source].endpoints.pluck(:slug)).to contain_exactly("forecast")
      end

      it "installs with ZERO credentials (operator attaches them after)" do
        result = described_class.install("generic-graphql", account: account)

        source = result[:data_source]
        # The api_key template REQUIRES auth, yet install ships NO credential.
        expect(source.requires_auth).to be(true)
        expect(source.auth_scheme).to eq("api_key")
        expect(source.credentials.count).to eq(0)
        expect(account.ai_data_source_credentials.count).to eq(0)
      end

      it "persists no credential for an auth-free template either" do
        result = described_class.install("rss-feed", account: account)
        expect(result[:data_source].credentials.count).to eq(0)
      end

      it "honors a target_slug override so the same template can install twice" do
        first = described_class.install("rss-feed", account: account)
        second = described_class.install("rss-feed", account: account, target_slug: "rss-feed-2")

        expect(first[:data_source].slug).to eq("rss-feed")
        expect(second[:data_source].slug).to eq("rss-feed-2")
        expect(second[:created]).to be(true)
        expect(account.ai_data_sources.where(slug: %w[rss-feed rss-feed-2]).count).to eq(2)
      end

      describe "dry_run" do
        it "previews the materialization without persisting" do
          expect do
            result = described_class.install("open-meteo-weather", account: account, dry_run: true)

            expect(result[:dry_run]).to be(true)
            expect(result[:created]).to be(true)
            expect(result[:errors]).to be_empty
            expect(result[:data_source]).to be_a(Ai::DataSource)
            expect(result[:data_source]).not_to be_persisted
            expect(result[:updated_endpoints]).to eq([{ slug: "forecast", action: "create" }])
          end.not_to change(Ai::DataSource, :count)
        end

        it "persists no credentials on a dry_run preview" do
          expect do
            described_class.install("generic-graphql", account: account, dry_run: true)
          end.not_to change(Ai::DataSourceCredential, :count)
        end
      end
    end

    context "with an unknown slug" do
      it "returns the import-shaped error without raising" do
        result = nil
        expect do
          result = described_class.install("nope-not-real", account: account)
        end.not_to raise_error

        expect(result).to match(
          data_source: nil,
          created: false,
          updated_endpoints: [],
          dry_run: false,
          errors: ["unknown template: nope-not-real"]
        )
      end

      it "persists nothing for an unknown slug" do
        expect do
          described_class.install("nope-not-real", account: account)
        end.not_to change(Ai::DataSource, :count)
      end

      it "carries the dry_run flag through into the unknown-slug error shape" do
        result = described_class.install("nope-not-real", account: account, dry_run: true)
        expect(result[:dry_run]).to be(true)
        expect(result[:data_source]).to be_nil
        expect(result[:errors]).to eq(["unknown template: nope-not-real"])
      end
    end
  end

  # ── x-com-provider campaign (I4): X.com template ──────────────────────────
  # The generic credential-free / secret-scan / manifest-shape specs above
  # already cover "x-com" (it walks every template in .all). These specs pin
  # its OAuth2-authorization-code wiring, its read + write endpoints, and that
  # installing it is byte-for-byte the same path every other template uses.
  describe "the x-com template" do
    it "is present in .all and findable by slug" do
      expect(described_class.all.map { |t| t[:slug] }).to include("x-com")
      tpl = described_class.find("x-com")
      expect(tpl).to be_a(Hash)
      expect(tpl[:name]).to eq("X.com")
    end

    it "selects the oauth2_authorization_code broker and carries a reconciled auth_config" do
      source = described_class.find("x-com")[:manifest]["source"]

      expect(source["requires_auth"]).to be(true)
      expect(source["auth_scheme"]).to eq("bearer")

      auth_config = source["auth_config"]
      # I1's connect flow (OauthAuthorizationCodeService) reads these TOP-LEVEL keys.
      expect(auth_config["authorize_url"]).to eq("https://twitter.com/i/oauth2/authorize")
      expect(auth_config["token_url"]).to eq("https://api.twitter.com/2/oauth2/token")
      expect(auth_config["scope"]).to eq("tweet.read tweet.write users.read offline.access")
      # I3's broker (Oauth2AuthorizationCodeBroker) reads the NESTED "broker" hash,
      # selected via the standard auth_config["broker"]["type"] mechanism.
      expect(auth_config["broker"]).to eq(
        "type" => "oauth2_authorization_code",
        "token_url" => "https://api.twitter.com/2/oauth2/token"
      )
      expect(Ai::DataSources::Credentials::Registry.for(auth_config["broker"]["type"]))
        .to be_a(Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker)
    end

    it "ships NO credential material despite requiring auth" do
      result = described_class.install("x-com", account: account)

      expect(result[:errors]).to be_empty
      source = result[:data_source]
      expect(source.requires_auth).to be(true)
      expect(source.credentials.count).to eq(0)
      expect(account.ai_data_source_credentials.count).to eq(0)
    end

    it "installs via the same ConfigPortabilityService path as every other template" do
      result = described_class.install("x-com", account: account)

      expect(result[:created]).to be(true)
      expect(result[:dry_run]).to be(false)
      source = result[:data_source]
      expect(source).to be_a(Ai::DataSource)
      expect(source).to be_persisted
      expect(source.slug).to eq("x-com")
      expect(source.source_type).to eq("x_com")
      expect(result[:updated_endpoints].map { |e| e[:slug] })
        .to contain_exactly("recent-search", "user-tweets", "create-post", "post-metrics")
    end

    it "survives the import sanitizer's auth_config allowlist round-trip unchanged" do
      # This is the exact reconciliation risk: ConfigPortabilityService#import
      # re-sanitizes auth_config against AUTH_CONFIG_ALLOWED_KEYS, so any key not
      # explicitly allowlisted is silently dropped on install.
      result = described_class.install("x-com", account: account)

      auth_config = result[:data_source].auth_config
      expect(auth_config["authorize_url"]).to eq("https://twitter.com/i/oauth2/authorize")
      expect(auth_config["token_url"]).to eq("https://api.twitter.com/2/oauth2/token")
      expect(auth_config["scope"]).to eq("tweet.read tweet.write users.read offline.access")
      expect(auth_config["broker"]["type"]).to eq("oauth2_authorization_code")
      expect(auth_config["broker"]["token_url"]).to eq("https://api.twitter.com/2/oauth2/token")
    end

    describe "runtime alignment (read + write endpoints)" do
      it "builds the recent-search GET request with the query placeholder substituted" do
        result = described_class.install("x-com", account: account)
        endpoint = result[:data_source].endpoints.find_by!(slug: "recent-search")

        req = Ai::DataSources::Adapters::RestAdapter.new.build_request(
          endpoint: endpoint, params: { "query" => "from:openai" }
        )

        expect(req[:method]).to eq("GET")
        expect(req[:query]["query"]).to eq("from:openai")
      end

      it "extracts recent-search records via response_mapping" do
        endpoint = described_class.install("x-com", account: account)[:data_source]
                                   .endpoints.find_by!(slug: "recent-search")
        body = '{"data":[{"id":"1","text":"hello"}],"meta":{"result_count":1}}'

        records = Ai::DataSources::Decoders::Json.new.decode(body, endpoint: endpoint)

        expect(records).to eq([{ "id" => "1", "text" => "hello" }])
      end

      it "builds the create-post POST request with the text placeholder in the body" do
        result = described_class.install("x-com", account: account)
        endpoint = result[:data_source].endpoints.find_by!(slug: "create-post")

        req = Ai::DataSources::Adapters::RestAdapter.new.build_request(
          endpoint: endpoint, params: { "text" => "hello world" }
        )

        expect(req[:method]).to eq("POST")
        expect(req[:body]).to eq("text" => "hello world")
      end

      it "marks the create-post endpoint as never-cache, side-effecting, and publish-capturing" do
        endpoint = described_class.install("x-com", account: account)[:data_source]
                                   .endpoints.find_by!(slug: "create-post")

        expect(endpoint.cache_ttl_seconds).to eq(0)
        expect(endpoint.metadata["side_effecting"]).to be(true)
        expect(endpoint.metadata["captures_published_post"]).to be(true)
      end

      it "marks the post-metrics endpoint as an engagement-metrics source" do
        endpoint = described_class.install("x-com", account: account)[:data_source]
                                   .endpoints.find_by!(slug: "post-metrics")

        expect(endpoint.http_method).to eq("GET")
        expect(endpoint.metadata["engagement_metrics"]).to be(true)
      end
    end
  end

  # ── provider-wave-2 (W1): LinkedIn / Reddit / YouTube ─────────────────────
  # Same seam as x-com (oauth2_authorization_code broker) — these specs pin
  # each template's auth_config wiring and that install/endpoints land exactly
  # like every other template. The generic credential-free / secret-scan /
  # manifest-shape specs above already cover all three (they walk .all).
  describe "the linkedin template" do
    it "is present in .all and findable by slug" do
      expect(described_class.all.map { |t| t[:slug] }).to include("linkedin")
      expect(described_class.find("linkedin")[:name]).to eq("LinkedIn")
    end

    it "selects the oauth2_authorization_code broker and carries a reconciled auth_config" do
      result = described_class.install("linkedin", account: account)
      auth_config = result[:data_source].auth_config

      expect(result[:data_source].requires_auth).to be(true)
      expect(result[:data_source].auth_scheme).to eq("bearer")
      expect(auth_config["authorize_url"]).to eq("https://www.linkedin.com/oauth/v2/authorization")
      expect(auth_config["token_url"]).to eq("https://www.linkedin.com/oauth/v2/accessToken")
      expect(auth_config["scope"]).to eq("openid profile email w_member_social")
      expect(auth_config["broker"]["type"]).to eq("oauth2_authorization_code")
      expect(Ai::DataSources::Credentials::Registry.for(auth_config["broker"]["type"]))
        .to be_a(Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker)
    end

    it "installs with ZERO credentials and the read + write endpoints" do
      result = described_class.install("linkedin", account: account)

      expect(result[:errors]).to be_empty
      expect(result[:data_source].credentials.count).to eq(0)
      expect(result[:updated_endpoints].map { |e| e[:slug] }).to contain_exactly("profile", "create-post")
    end

    it "marks the create-post endpoint as never-cache and side-effecting" do
      endpoint = described_class.install("linkedin", account: account)[:data_source]
                                 .endpoints.find_by!(slug: "create-post")

      expect(endpoint.cache_ttl_seconds).to eq(0)
      expect(endpoint.metadata["side_effecting"]).to be(true)
    end
  end

  describe "the reddit template" do
    it "is present in .all and findable by slug" do
      expect(described_class.all.map { |t| t[:slug] }).to include("reddit")
      expect(described_class.find("reddit")[:name]).to eq("Reddit")
    end

    it "selects the oauth2_authorization_code broker and carries a reconciled auth_config" do
      result = described_class.install("reddit", account: account)
      auth_config = result[:data_source].auth_config

      expect(result[:data_source].requires_auth).to be(true)
      expect(result[:data_source].auth_scheme).to eq("bearer")
      expect(auth_config["authorize_url"]).to eq("https://www.reddit.com/api/v1/authorize")
      expect(auth_config["token_url"]).to eq("https://www.reddit.com/api/v1/access_token")
      expect(auth_config["scope"]).to eq("read submit identity")
      expect(auth_config["broker"]["type"]).to eq("oauth2_authorization_code")
      expect(Ai::DataSources::Credentials::Registry.for(auth_config["broker"]["type"]))
        .to be_a(Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker)
    end

    it "installs with ZERO credentials and the read + write endpoints" do
      result = described_class.install("reddit", account: account)

      expect(result[:errors]).to be_empty
      expect(result[:data_source].credentials.count).to eq(0)
      expect(result[:updated_endpoints].map { |e| e[:slug] }).to contain_exactly("subreddit-new", "submit-post")
    end

    it "marks the submit-post endpoint as never-cache and side-effecting" do
      endpoint = described_class.install("reddit", account: account)[:data_source]
                                 .endpoints.find_by!(slug: "submit-post")

      expect(endpoint.cache_ttl_seconds).to eq(0)
      expect(endpoint.metadata["side_effecting"]).to be(true)
    end
  end

  describe "the youtube template" do
    it "is present in .all and findable by slug" do
      expect(described_class.all.map { |t| t[:slug] }).to include("youtube")
      expect(described_class.find("youtube")[:name]).to eq("YouTube")
    end

    it "selects the oauth2_authorization_code broker and carries a reconciled auth_config" do
      result = described_class.install("youtube", account: account)
      auth_config = result[:data_source].auth_config

      expect(result[:data_source].requires_auth).to be(true)
      expect(result[:data_source].auth_scheme).to eq("bearer")
      expect(auth_config["authorize_url"]).to eq("https://accounts.google.com/o/oauth2/v2/auth")
      expect(auth_config["token_url"]).to eq("https://oauth2.googleapis.com/token")
      expect(auth_config["scope"]).to eq("https://www.googleapis.com/auth/youtube.readonly")
      expect(auth_config["broker"]["type"]).to eq("oauth2_authorization_code")
      expect(Ai::DataSources::Credentials::Registry.for(auth_config["broker"]["type"]))
        .to be_a(Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker)
    end

    it "installs with ZERO credentials and a read-only endpoint (publish deferred for W1)" do
      result = described_class.install("youtube", account: account)

      expect(result[:errors]).to be_empty
      expect(result[:data_source].credentials.count).to eq(0)
      expect(result[:updated_endpoints].map { |e| e[:slug] }).to contain_exactly("search-videos")
    end
  end
end
