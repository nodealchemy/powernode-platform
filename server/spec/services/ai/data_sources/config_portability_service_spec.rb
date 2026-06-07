# frozen_string_literal: true

require "rails_helper"

# Phase 4b-3b onboarding portability. Ai::DataSources::ConfigPortabilityService
# turns a configured Ai::DataSource (+ its endpoints) into a CREDENTIAL-FREE,
# portable MANIFEST and back, and layers append-only config versioning + rollback
# on top of Ai::DataSourceConfigVersion.
#
# The dominant concern here is the ABSOLUTE SECURITY CONSTRAINT: the export
# manifest must NEVER carry secret material — not the credentials association, not
# secret-ish auth_config values (client_secret / api_key / web_identity_token /
# ...), and not a secret planted in any free-form jsonb column. Most of these
# examples are adversarial: they PLANT secrets in every place a secret could
# plausibly hide and then deep-scan the entire manifest to prove none of the
# secret VALUES survive.
#
# HERMETIC: the DataSource after_commit KG sync (Ai::DataSourceGraph::BridgeService
# #sync_data_source) would otherwise reach the embedding backend / Redis when a
# factory persists a source under DatabaseCleaner :deletion, so it is stubbed for
# the whole file (matching the sibling data-source service specs).
RSpec.describe Ai::DataSources::ConfigPortabilityService, type: :service do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # ── Shared secret sentinels ───────────────────────────────────────────────
  # Distinctive values planted across every secret-capable surface. The export
  # specs assert NONE of these strings appear ANYWHERE in the serialized manifest
  # (deep scan over every nested value).
  let(:secret_client_secret) { "SENTINEL-client-secret-abc123" }
  let(:secret_api_key)        { "SENTINEL-api-key-def456" }
  let(:secret_web_identity)   { "SENTINEL-web-identity-jwt.eyJ.sig" }
  let(:secret_in_config)      { "SENTINEL-config-secret-ghi789" }
  let(:secret_in_metadata)    { "SENTINEL-metadata-apikey-jkl012" }
  let(:secret_in_params)      { "SENTINEL-default-param-token-mno345" }
  let(:secret_nested_token)   { "SENTINEL-nested-broker-token-pqr678" }
  let(:secret_external_id)    { "SENTINEL-sts-external-id-stu901" }

  # Recursively collect every scalar value reachable inside a manifest so a single
  # assertion can prove a secret VALUE leaked nowhere — at any nesting depth.
  def deep_values(node)
    case node
    when Hash
      node.values.flat_map { |v| deep_values(v) }
    when Array
      node.flat_map { |v| deep_values(v) }
    else
      [node]
    end
  end

  # Recursively collect every Hash KEY reachable inside a manifest (stringified),
  # so we can assert secret-KEYED entries were scrubbed from the free-form jsonb.
  def deep_keys(node)
    case node
    when Hash
      node.keys.map(&:to_s) + node.values.flat_map { |v| deep_keys(v) }
    when Array
      node.flat_map { |v| deep_keys(v) }
    else
      []
    end
  end

  # A source loaded with secrets in EVERY place a secret could hide:
  #   - a real Ai::DataSourceCredential (the credentials association)
  #   - auth_config secret values (client_secret / api_key / web_identity_token)
  #     PLUS a confused-deputy external_id PLUS a vault_path reference PLUS
  #     non-secret broker knobs (token_url / role_arn) PLUS a nested secret token
  #   - secrets planted in the free-form jsonb (configuration / metadata /
  #     default_parameters), each under a secret-NAMED key
  let(:loaded_source) do
    src = create(
      :ai_data_source,
      account: account,
      name: "Loaded Source",
      slug: "loaded-source",
      source_type: "custom",
      auth_scheme: "aws_sts_web_identity",
      requires_auth: true,
      auth_config: {
        "type" => "aws_sts_web_identity",
        "token_url" => "https://sts.amazonaws.com",
        "role_arn" => "arn:aws:iam::123456789012:role/portable",
        "region" => "us-east-1",
        "vault_path" => "secret/data/ai/data_sources/loaded",
        "client_secret" => secret_client_secret,
        "api_key" => secret_api_key,
        "web_identity_token" => secret_web_identity,
        "external_id" => secret_external_id,
        "broker" => {
          "token_url" => "https://broker.example.com/token",
          "role_arn" => "arn:aws:iam::123456789012:role/broker",
          "token" => secret_nested_token
        }
      },
      configuration: {
        "page_size" => 50,
        "secret" => secret_in_config
      },
      metadata: {
        "owner" => "data-team",
        "api_key" => secret_in_metadata
      },
      default_parameters: {
        "format" => "json",
        "nested" => { "token" => secret_in_params }
      }
    )
    create(:ai_data_source_endpoint, data_source: src, name: "Items", slug: "items")
    create(:ai_data_source_credential, :with_secret, account: account, data_source: src)
    src
  end

  # ────────────────────────────────────────────────────────────────────────────
  # #export — CREDENTIAL-FREE manifest (the security core)
  # ────────────────────────────────────────────────────────────────────────────
  describe "#export" do
    subject(:manifest) { service.export(loaded_source) }

    it "stamps the manifest version" do
      expect(manifest["manifest_version"]).to eq(described_class::MANIFEST_VERSION)
    end

    it "leaves exported_at nil so the manifest is byte-stable across exports" do
      expect(manifest).to have_key("exported_at")
      expect(manifest["exported_at"]).to be_nil
    end

    it "produces a string-keyed source hash" do
      expect(manifest["source"]).to be_a(Hash)
      expect(manifest["source"].keys).to all(be_a(String))
    end

    it "is byte-stable across repeated exports (same input -> identical manifest)" do
      expect(service.export(loaded_source)).to eq(manifest)
    end

    # ── credential association is NEVER traversed ──
    context "credential safety" do
      it "carries NO credential record / credentials key in the manifest" do
        expect(manifest).not_to have_key("credentials")
        expect(manifest["source"]).not_to have_key("credentials")
      end

      it "exports even though the source has a persisted credential" do
        expect(loaded_source.credentials.count).to eq(1)
        expect(manifest["source"]["name"]).to eq("Loaded Source")
      end
    end

    # ── THE deep scan: no secret VALUE anywhere, at any depth ──
    context "deep secret-value scan" do
      it "contains NONE of the planted secret values anywhere in the manifest" do
        values = deep_values(manifest)
        [
          secret_client_secret, secret_api_key, secret_web_identity,
          secret_in_config, secret_in_metadata, secret_in_params,
          secret_nested_token, secret_external_id
        ].each do |secret|
          expect(values).not_to include(secret)
        end
      end

      it "does not leak the auth_config client_secret" do
        expect(deep_values(manifest)).not_to include(secret_client_secret)
      end

      it "does not leak the auth_config api_key" do
        expect(deep_values(manifest)).not_to include(secret_api_key)
      end

      it "does not leak the auth_config web_identity_token (raw JWT)" do
        expect(deep_values(manifest)).not_to include(secret_web_identity)
      end

      it "does not leak a secret planted in configuration jsonb" do
        expect(deep_values(manifest)).not_to include(secret_in_config)
      end

      it "does not leak a secret planted in metadata jsonb" do
        expect(deep_values(manifest)).not_to include(secret_in_metadata)
      end

      it "does not leak a secret nested inside default_parameters jsonb" do
        expect(deep_values(manifest)).not_to include(secret_in_params)
      end

      it "does not leak a secret nested inside the broker hash" do
        expect(deep_values(manifest)).not_to include(secret_nested_token)
      end
    end

    # ── free-form jsonb: secret-KEYED entries scrubbed, non-secret kept ──
    context "scrub_value over free-form jsonb columns" do
      it "strips the secret-keyed entry from configuration but keeps non-secret knobs" do
        expect(manifest["source"]["configuration"]).to eq("page_size" => 50)
        expect(manifest["source"]["configuration"]).not_to have_key("secret")
      end

      it "strips the secret-keyed entry from metadata but keeps non-secret knobs" do
        expect(manifest["source"]["metadata"]).to eq("owner" => "data-team")
        expect(manifest["source"]["metadata"]).not_to have_key("api_key")
      end

      it "strips a nested secret key from default_parameters, keeping the structure" do
        expect(manifest["source"]["default_parameters"]).to eq(
          "format" => "json",
          "nested" => {}
        )
      end

      it "leaves no secret-named key anywhere in the manifest" do
        secret_named = deep_keys(manifest).select do |k|
          %w[secret api_key token client_secret web_identity_token].include?(k)
        end
        expect(secret_named).to be_empty
      end
    end

    # ── auth_config sanitization: name + non-secret knobs + vault_path ──
    context "auth_config sanitization" do
      subject(:auth_config) { manifest["source"]["auth_config"] }

      it "keeps the non-secret token_url knob" do
        expect(auth_config["token_url"]).to eq("https://sts.amazonaws.com")
      end

      it "keeps the non-secret role_arn knob" do
        expect(auth_config["role_arn"]).to eq("arn:aws:iam::123456789012:role/portable")
      end

      it "keeps the non-secret region knob" do
        expect(auth_config["region"]).to eq("us-east-1")
      end

      it "keeps the type discriminator" do
        expect(auth_config["type"]).to eq("aws_sts_web_identity")
      end

      # vault_path is a REFERENCE to where material lives, not the material itself.
      # The implementation intentionally allowlists it (AUTH_CONFIG_ALLOWED_KEYS),
      # so the importing operator knows where the credential is brokered from. We
      # document and assert that behavior here.
      it "keeps vault_path (a reference handle, not secret material)" do
        expect(auth_config["vault_path"]).to eq("secret/data/ai/data_sources/loaded")
      end

      it "drops the auth_config client_secret key entirely" do
        expect(auth_config).not_to have_key("client_secret")
      end

      it "drops the auth_config api_key key entirely" do
        expect(auth_config).not_to have_key("api_key")
      end

      it "drops the auth_config web_identity_token key entirely" do
        expect(auth_config).not_to have_key("web_identity_token")
      end

      # external_id is a confused-deputy SHARED SECRET (re-supplied with the
      # credential on import), deliberately EXCLUDED from the allowlist.
      it "drops external_id (confused-deputy shared secret, not a portable knob)" do
        expect(auth_config).not_to have_key("external_id")
      end

      it "sanitizes the nested broker to its non-secret knobs only" do
        expect(auth_config["broker"]).to eq(
          "token_url" => "https://broker.example.com/token",
          "role_arn" => "arn:aws:iam::123456789012:role/broker"
        )
      end

      it "drops the secret token nested in the broker" do
        expect(auth_config["broker"]).not_to have_key("token")
      end
    end

    # ── exports the auth_scheme NAME (not material) ──
    it "keeps the auth_scheme name" do
      expect(manifest["source"]["auth_scheme"]).to eq("aws_sts_web_identity")
    end

    # ── identity / runtime / usage columns excluded ──
    context "excluded identity and runtime columns" do
      let(:tracked_source) do
        create(
          :ai_data_source, account: account, name: "Tracked", slug: "tracked",
          health_status: "degraded", usage_count: 7,
          positive_usage_count: 5, negative_usage_count: 2,
          effectiveness_score: 0.82, last_used_at: 2.hours.ago
        )
      end
      subject(:src) { service.export(tracked_source)["source"] }

      it "excludes id" do
        expect(src).not_to have_key("id")
      end

      it "excludes account_id" do
        expect(src).not_to have_key("account_id")
      end

      it "excludes created_at / updated_at" do
        expect(src).not_to have_key("created_at")
        expect(src).not_to have_key("updated_at")
      end

      it "excludes health_status and last_health_check_at" do
        expect(src).not_to have_key("health_status")
        expect(src).not_to have_key("last_health_check_at")
      end

      it "excludes last_used_at" do
        expect(src).not_to have_key("last_used_at")
      end

      it "excludes effectiveness_score and the usage counters" do
        expect(src).not_to have_key("effectiveness_score")
        expect(src).not_to have_key("usage_count")
        expect(src).not_to have_key("positive_usage_count")
        expect(src).not_to have_key("negative_usage_count")
      end
    end

    # ── only allowlisted source keys appear ──
    it "exports ONLY allowlisted source keys (plus the sanitized auth_config)" do
      allowed = (described_class::SOURCE_EXPORT_KEYS + %w[auth_config]).uniq
      expect(manifest["source"].keys - allowed).to be_empty
      # auth_config is always present (sanitized, possibly {}).
      expect(manifest["source"]).to have_key("auth_config")
    end

    # ── endpoints ──
    context "endpoints" do
      it "exports the source's endpoints ordered by slug" do
        loaded_source.endpoints.create!(name: "Alpha", slug: "alpha", http_method: "GET")
        slugs = service.export(loaded_source)["endpoints"].map { |e| e["slug"] }
        expect(slugs).to eq(slugs.sort)
        expect(slugs).to include("alpha", "items")
      end

      it "exports ONLY allowlisted endpoint keys" do
        ep = manifest["endpoints"].first
        expect(ep.keys - described_class::ENDPOINT_EXPORT_KEYS).to be_empty
      end

      it "excludes endpoint id / ai_data_source_id / timestamps" do
        ep = manifest["endpoints"].first
        expect(ep).not_to have_key("id")
        expect(ep).not_to have_key("ai_data_source_id")
        expect(ep).not_to have_key("created_at")
        expect(ep).not_to have_key("updated_at")
      end

      it "scrubs secrets planted in endpoint free-form jsonb (metadata)" do
        loaded_source.endpoints.first.update!(
          metadata: { "label" => "primary", "api_key" => "SENTINEL-endpoint-secret" }
        )
        ep = service.export(loaded_source)["endpoints"].find { |e| e["slug"] == "items" }
        expect(ep["metadata"]).to eq("label" => "primary")
        expect(deep_values(service.export(loaded_source))).not_to include("SENTINEL-endpoint-secret")
      end

      it "returns an empty endpoints array when the source has none" do
        bare = create(:ai_data_source, account: account, name: "Bare", slug: "bare")
        expect(service.export(bare)["endpoints"]).to eq([])
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # #import — round-trip, upsert, credential-free, account scoping, dry_run
  # ────────────────────────────────────────────────────────────────────────────
  describe "#import" do
    # A clean, hand-built manifest (string keys) for the common import paths.
    let(:manifest) do
      {
        "manifest_version" => 1,
        "source" => {
          "name" => "Portable Weather",
          "slug" => "portable-weather",
          "source_type" => "open_meteo",
          "protocol" => "rest",
          "api_base_url" => "https://api.open-meteo.com",
          "description" => "Imported source",
          "is_active" => true,
          "requires_auth" => false,
          "auth_scheme" => "none",
          "configuration" => { "units" => "metric" },
          "metadata" => { "team" => "weather" },
          "auth_config" => {}
        },
        "endpoints" => [
          {
            "name" => "Forecast",
            "slug" => "forecast",
            "http_method" => "GET",
            "path_template" => "/v1/forecast",
            "response_format" => "json"
          },
          {
            "name" => "History",
            "slug" => "history",
            "http_method" => "GET",
            "path_template" => "/v1/history",
            "response_format" => "json"
          }
        ],
        "exported_at" => nil
      }
    end

    context "creating a new source" do
      it "creates the source under the importing account" do
        result = service.import(manifest)
        expect(result[:created]).to be(true)
        expect(result[:errors]).to be_empty
        ds = result[:data_source]
        expect(ds).to be_persisted
        expect(ds.account_id).to eq(account.id)
        expect(ds.slug).to eq("portable-weather")
        expect(ds.source_type).to eq("open_meteo")
      end

      it "applies allowlisted source attributes" do
        ds = service.import(manifest)[:data_source]
        expect(ds.api_base_url).to eq("https://api.open-meteo.com")
        expect(ds.configuration).to eq("units" => "metric")
        expect(ds.metadata).to eq("team" => "weather")
      end

      it "creates the manifest's endpoints" do
        result = service.import(manifest)
        ds = result[:data_source]
        expect(ds.endpoints.pluck(:slug)).to match_array(%w[forecast history])
        expect(result[:updated_endpoints]).to match_array(
          [{ slug: "forecast", action: "create" }, { slug: "history", action: "create" }]
        )
      end

      it "NEVER creates credentials on import" do
        ds = service.import(manifest)[:data_source]
        expect(ds.credentials.count).to eq(0)
      end

      it "tolerates a symbol-keyed manifest" do
        sym = manifest.deep_symbolize_keys
        result = service.import(sym)
        expect(result[:errors]).to be_empty
        expect(result[:data_source].slug).to eq("portable-weather")
      end
    end

    context "round-trip into a DIFFERENT account" do
      it "reproduces an equivalent source + endpoints (allowlisted attrs match)" do
        # Export from `account`, import into `other_account`.
        exported = service.export(loaded_source)
        importer = described_class.new(account: other_account)
        result = importer.import(exported)

        expect(result[:errors]).to be_empty
        clone = result[:data_source]
        expect(clone.account_id).to eq(other_account.id)

        # Allowlisted source attrs round-trip identically (re-export the clone and
        # compare manifests; both have exported_at nil so they are comparable).
        reexported = described_class.new(account: other_account).export(clone)
        expect(reexported["source"]).to eq(exported["source"])
      end

      it "reproduces the endpoints by slug in the new account" do
        exported = service.export(loaded_source)
        result = described_class.new(account: other_account).import(exported)
        expect(result[:data_source].endpoints.pluck(:slug)).to eq(
          exported["endpoints"].map { |e| e["slug"] }
        )
      end

      it "still creates NO credentials when importing a manifest from a source that had one" do
        expect(loaded_source.credentials.count).to eq(1)
        exported = service.export(loaded_source)
        result = described_class.new(account: other_account).import(exported)
        expect(result[:data_source].credentials.count).to eq(0)
      end
    end

    context "endpoint upsert by slug (no duplicates on re-import)" do
      it "updates rather than duplicates endpoints on a second import" do
        first = service.import(manifest)
        ds = first[:data_source]
        expect(ds.endpoints.count).to eq(2)

        # Re-import the SAME manifest — endpoints are matched by slug and updated.
        second = service.import(manifest)
        expect(second[:created]).to be(false)
        expect(second[:data_source].endpoints.count).to eq(2)
        expect(second[:updated_endpoints]).to match_array(
          [{ slug: "forecast", action: "update" }, { slug: "history", action: "update" }]
        )
      end

      it "applies updated endpoint attributes in place" do
        service.import(manifest)
        manifest["endpoints"].first["path_template"] = "/v2/forecast"
        service.import(manifest)
        ep = account.ai_data_sources.find_by(slug: "portable-weather")
                    .endpoints.find_by(slug: "forecast")
        expect(ep.path_template).to eq("/v2/forecast")
      end

      it "records an error for an endpoint missing a slug (rolls the import back)" do
        manifest["endpoints"] << { "name" => "NoSlug", "http_method" => "GET" }
        result = service.import(manifest)
        expect(result[:errors]).to include(a_string_matching(/endpoint missing slug/))
        # transactional: the whole import rolls back, no source persisted.
        expect(account.ai_data_sources.where(slug: "portable-weather")).not_to exist
      end
    end

    context "name de-dup when cloning under an override slug into the SAME account" do
      it "appends a numeric suffix so the per-account name uniqueness holds" do
        # Original lives at slug "loaded-source" / name "Loaded Source".
        exported = service.export(loaded_source)
        # Clone into the SAME account under a different slug — the name would
        # otherwise collide (name is unique per account).
        result = service.import(exported, slug: "loaded-source-copy")
        expect(result[:errors]).to be_empty
        clone = result[:data_source]
        expect(clone.slug).to eq("loaded-source-copy")
        expect(clone.name).to eq("Loaded Source (2)")
        expect(clone.id).not_to eq(loaded_source.id)
      end

      it "increments further when the (2) name is also taken" do
        exported = service.export(loaded_source)
        service.import(exported, slug: "loaded-source-copy")     # -> "Loaded Source (2)"
        result = service.import(exported, slug: "loaded-source-copy-2")
        expect(result[:data_source].name).to eq("Loaded Source (3)")
      end

      it "keeps the existing name on an in-place update (same slug, no self-collision)" do
        exported = service.export(loaded_source)
        result = service.import(exported, slug: "loaded-source")
        expect(result[:created]).to be(false)
        expect(result[:data_source].id).to eq(loaded_source.id)
        expect(result[:data_source].name).to eq("Loaded Source")
      end
    end

    context "account scoping" do
      it "cannot touch another account's source with the same slug (creates its own)" do
        # other_account owns a source at slug "shared-slug".
        other = described_class.new(account: other_account)
        other.import(manifest.merge("source" => manifest["source"].merge("slug" => "shared-slug")))
        foreign = other_account.ai_data_sources.find_by(slug: "shared-slug")
        expect(foreign).to be_present

        # Importing the same slug from `account` creates a SEPARATE record scoped
        # to `account`, leaving the foreign source untouched.
        result = service.import(manifest.merge("source" => manifest["source"].merge("slug" => "shared-slug")))
        expect(result[:created]).to be(true)
        mine = account.ai_data_sources.find_by(slug: "shared-slug")
        expect(mine.id).not_to eq(foreign.id)
        expect(mine.account_id).to eq(account.id)
      end

      it "ignores any account_id smuggled in the manifest source" do
        tampered = manifest.deep_dup
        tampered["source"]["account_id"] = other_account.id
        result = service.import(tampered)
        expect(result[:data_source].account_id).to eq(account.id)
      end

      it "never imports credentials even if a manifest hand-adds a credentials key" do
        tampered = manifest.deep_dup
        tampered["credentials"] = [{ "name" => "smuggled", "encrypted_api_key" => "x" }]
        result = service.import(tampered)
        expect(result[:data_source].credentials.count).to eq(0)
      end
    end

    context "hand-edited manifest cannot smuggle a secret into the stored record" do
      it "strips a secret auth_config value on import (defense in depth)" do
        tampered = manifest.deep_dup
        tampered["source"]["auth_config"] = {
          "token_url" => "https://broker/token",
          "client_secret" => "SENTINEL-smuggled-secret"
        }
        ds = service.import(tampered)[:data_source]
        expect(ds.auth_config).to eq("token_url" => "https://broker/token")
        expect(ds.auth_config).not_to have_key("client_secret")
      end

      it "drops a non-allowlisted source attribute on import" do
        tampered = manifest.deep_dup
        tampered["source"]["effectiveness_score"] = 0.99
        ds = service.import(tampered)[:data_source]
        # effectiveness_score is not in SOURCE_EXPORT_KEYS, so the manifest value
        # is ignored; the model keeps its own default.
        expect(ds.effectiveness_score).not_to eq(0.99)
      end
    end

    context "invalid manifests" do
      it "returns an error when the source has no slug" do
        bad = manifest.deep_dup
        bad["source"].delete("slug")
        bad["source"].delete("name") # also no name to derive a slug from
        result = service.import(bad)
        expect(result[:data_source]).to be_nil
        expect(result[:errors]).to include(a_string_matching(/missing a slug/))
      end

      it "normalizes a manifest missing source/endpoints rather than raising" do
        result = service.import({ "manifest_version" => 1 })
        expect(result[:data_source]).to be_nil
        expect(result[:errors]).to be_present
      end
    end

    context "dry_run" do
      it "returns a preview and persists NOTHING" do
        before_count = Ai::DataSource.count
        before_eps = Ai::DataSourceEndpoint.count

        result = service.import(manifest, dry_run: true)

        expect(result[:dry_run]).to be(true)
        expect(result[:created]).to be(true)
        expect(result[:data_source]).not_to be_persisted
        expect(result[:updated_endpoints]).to match_array(
          [{ slug: "forecast", action: "create" }, { slug: "history", action: "create" }]
        )
        # No DB row count change at all.
        expect(Ai::DataSource.count).to eq(before_count)
        expect(Ai::DataSourceEndpoint.count).to eq(before_eps)
      end

      it "previews an update against an existing source without persisting" do
        service.import(manifest) # create for real first
        manifest["source"]["description"] = "changed in dry-run"
        manifest["endpoints"].first["path_template"] = "/v9/forecast"

        before_count = Ai::DataSource.count
        result = service.import(manifest, dry_run: true)

        expect(result[:created]).to be(false)
        expect(result[:updated_endpoints]).to include(slug: "forecast", action: "update")
        # The persisted record is unchanged.
        persisted = account.ai_data_sources.find_by(slug: "portable-weather")
        expect(persisted.description).to eq("Imported source")
        expect(persisted.endpoints.find_by(slug: "forecast").path_template).to eq("/v1/forecast")
        expect(Ai::DataSource.count).to eq(before_count)
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # #snapshot! — append a credential-free config version
  # ────────────────────────────────────────────────────────────────────────────
  describe "#snapshot!" do
    let(:source) { create(:ai_data_source, account: account, name: "Snap", slug: "snap") }

    it "persists an Ai::DataSourceConfigVersion" do
      expect { service.snapshot!(source) }
        .to change { Ai::DataSourceConfigVersion.count }.by(1)
    end

    it "captures sequential version numbers (1, then 2)" do
      v1 = service.snapshot!(source)
      v2 = service.snapshot!(source)
      expect(v1.version).to eq(1)
      expect(v2.version).to eq(2)
    end

    it "scopes the version row to the importing account and source" do
      version = service.snapshot!(source)
      expect(version.account_id).to eq(account.id)
      expect(version.ai_data_source_id).to eq(source.id)
    end

    it "records the created_by_type (default manual)" do
      expect(service.snapshot!(source).created_by_type).to eq("manual")
    end

    it "honors an explicit created_by_type and note" do
      version = service.snapshot!(source, created_by_type: "auto", note: "nightly")
      expect(version.created_by_type).to eq("auto")
      expect(version.note).to eq("nightly")
    end

    it "stamps exported_at on the stored manifest (unlike a bare export)" do
      version = service.snapshot!(source)
      expect(version.manifest["exported_at"]).to be_present
    end

    it "stores a SECRET-FREE manifest even when the source carries secrets" do
      # Reuse the fully-loaded source so every secret surface is present.
      version = service.snapshot!(loaded_source)
      values = deep_values(version.manifest)
      [
        secret_client_secret, secret_api_key, secret_web_identity,
        secret_in_config, secret_in_metadata, secret_in_params,
        secret_nested_token, secret_external_id
      ].each { |secret| expect(values).not_to include(secret) }
    end

    it "keeps the snapshot manifest credential-free (no credentials key)" do
      version = service.snapshot!(loaded_source)
      expect(version.manifest).not_to have_key("credentials")
      expect(version.manifest["source"]).not_to have_key("credentials")
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # #rollback! — restore a prior config version (reversibly, on success only)
  # ────────────────────────────────────────────────────────────────────────────
  describe "#rollback!" do
    let(:source) do
      create(:ai_data_source, account: account, name: "Roller", slug: "roller",
                              description: "v1 description",
                              configuration: { "stage" => "one" })
    end

    it "restores the source config to the snapshotted version" do
      service.snapshot!(source)               # v1 captures "v1 description"/stage one
      v1 = source.config_versions.order(:version).first.version

      source.update!(description: "v2 description", configuration: { "stage" => "two" })

      result = service.rollback!(source, v1)
      expect(result[:errors]).to be_empty
      expect(result[:restored_version]).to eq(v1)

      source.reload
      expect(source.description).to eq("v1 description")
      expect(source.configuration).to eq("stage" => "one")
    end

    it "records a pre-rollback 'rollback' snapshot ONLY on success (reversibility)" do
      service.snapshot!(source) # v1
      source.update!(description: "v2 description")

      expect { service.rollback!(source, 1) }
        .to change { source.config_versions.where(created_by_type: "rollback").count }.by(1)

      pre = source.config_versions.where(created_by_type: "rollback").order(:version).last
      # The pre-rollback snapshot captured the v2 state (what we rolled away from).
      expect(pre.manifest["source"]["description"]).to eq("v2 description")
      expect(pre.note).to match(/pre-rollback/)
    end

    it "resolves a version record (not just an integer)" do
      record = service.snapshot!(source) # v1 record
      source.update!(description: "v2 description")
      result = service.rollback!(source, record)
      expect(result[:restored_version]).to eq(record.version)
      expect(source.reload.description).to eq("v1 description")
    end

    it "returns {error:} when the version is not found for this source" do
      result = service.rollback!(source, 999)
      expect(result[:error]).to match(/not found/)
      expect(result).not_to have_key(:restored_version)
    end

    it "refuses a version belonging to a DIFFERENT account's source" do
      foreign_source = create(:ai_data_source, account: other_account,
                                               name: "Foreign", slug: "foreign")
      foreign_version = described_class.new(account: other_account).snapshot!(foreign_source)
      # `service` is scoped to `account`; the foreign version must not resolve.
      result = service.rollback!(source, foreign_version)
      expect(result[:error]).to match(/not found/)
    end

    context "when the replay FAILS" do
      it "returns restored_version: nil + errors and leaves NO spurious rollback snapshot" do
        service.snapshot!(source) # v1
        version = source.config_versions.order(:version).first

        # Corrupt the historical manifest so the replayed import errors out: an
        # endpoint with no slug forces upsert_endpoints to record an error, which
        # rolls the import back (result[:errors] present).
        version.update!(manifest: version.manifest.merge(
          "endpoints" => [{ "name" => "BadEndpoint", "http_method" => "GET" }]
        ))

        source.update!(description: "v2 description")

        expect do
          result = service.rollback!(source, version.version)
          expect(result[:restored_version]).to be_nil
          expect(result[:errors]).to be_present
        end.not_to(change { source.config_versions.where(created_by_type: "rollback").count })

        # The failed replay rolled back: the source still holds the v2 description.
        expect(source.reload.description).to eq("v2 description")
      end

      it "does not restore config when the replay fails" do
        service.snapshot!(source) # v1
        version = source.config_versions.order(:version).first
        version.update!(manifest: version.manifest.merge(
          "endpoints" => [{ "name" => "BadEndpoint", "http_method" => "GET" }]
        ))

        source.update!(configuration: { "stage" => "two" })
        service.rollback!(source, version.version)
        # config untouched because the import (and thus the restore) rolled back.
        expect(source.reload.configuration).to eq("stage" => "two")
      end
    end
  end
end
