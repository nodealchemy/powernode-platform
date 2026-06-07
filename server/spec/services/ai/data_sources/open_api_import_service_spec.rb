# frozen_string_literal: true

require "rails_helper"

# OpenApiImportService turns a parsed OpenAPI 3 Hash into Ai::DataSourceEndpoint
# rows for a data source. There is no openapi/json-schema gem, so the spec is
# walked STRUCTURALLY: paths -> operations -> endpoints, with each operation's
# 2xx/default JSON response schema resolved against #/components ($ref chasing)
# and stored as the endpoint's response_schema.
#
# These specs are hermetic: the only side effects are endpoint rows, and the
# data-source -> knowledge-graph after_commit sync is stubbed so creating a
# source via the factory does not reach Redis/embeddings under DatabaseCleaner.
RSpec.describe Ai::DataSources::OpenApiImportService, type: :service do
  before do
    # Creating an ai_data_source fires an after_commit that syncs the source into
    # the knowledge graph (embedding -> Redis). Stub it so factory creates stay
    # in-process; otherwise the after_commit fires under DatabaseCleaner :deletion
    # and hits external services.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  let(:data_source) { create(:ai_data_source) }
  let(:service) { described_class.new(data_source) }

  # A compact OpenAPI 3 document exercising: operationId-named ops, a summary-only
  # op, a verb+path-named op, $ref response bodies, recursive ($ref-within-$ref)
  # component resolution, and multiple verbs under one path item.
  let(:spec) do
    {
      "openapi" => "3.0.0",
      "info" => { "title" => "Weather API", "version" => "1.0.0" },
      "paths" => {
        "/stations" => {
          "get" => {
            "operationId" => "listStations",
            "summary" => "List stations",
            "tags" => %w[stations],
            "responses" => {
              "200" => {
                "description" => "ok",
                "content" => {
                  "application/json" => {
                    "schema" => { "$ref" => "#/components/schemas/StationList" }
                  }
                }
              }
            }
          },
          "post" => {
            "summary" => "Create a station",
            "responses" => {
              "201" => {
                "content" => {
                  "application/json" => {
                    "schema" => { "$ref" => "#/components/schemas/Station" }
                  }
                }
              }
            }
          }
        },
        "/stations/{id}/observations" => {
          "get" => {
            # No operationId and no summary -> name falls back to "GET <path>".
            "responses" => {
              "default" => {
                "content" => {
                  "application/json" => {
                    "schema" => { "type" => "object", "properties" => { "ok" => { "type" => "boolean" } } }
                  }
                }
              }
            }
          }
        }
      },
      "components" => {
        "schemas" => {
          "StationList" => {
            "type" => "array",
            # Recursive $ref: array items reference another component schema.
            "items" => { "$ref" => "#/components/schemas/Station" }
          },
          "Station" => {
            "type" => "object",
            "required" => %w[id],
            "properties" => {
              "id" => { "type" => "string" },
              "name" => { "type" => "string" },
              "coords" => { "$ref" => "#/components/schemas/Coords" }
            }
          },
          "Coords" => {
            "type" => "object",
            "properties" => {
              "lat" => { "type" => "number" },
              "lon" => { "type" => "number" }
            }
          }
        }
      }
    }
  end

  describe "#import — parsing operations to endpoint attrs" do
    it "produces one preview per (path, method) operation" do
      result = service.import(spec, dry_run: true)

      expect(result[:preview].size).to eq(3)
      expect(result[:errors]).to be_empty
    end

    it "names an endpoint from its operationId when present" do
      preview = service.import(spec, dry_run: true)[:preview]
      get_stations = preview.find { |p| p[:path_template] == "/stations" && p[:http_method] == "GET" }

      expect(get_stations[:name]).to eq("listStations")
      expect(get_stations[:http_method]).to eq("GET")
      expect(get_stations[:path_template]).to eq("/stations")
      expect(get_stations[:response_format]).to eq("json")
    end

    it "falls back to the summary when there is no operationId" do
      preview = service.import(spec, dry_run: true)[:preview]
      post_station = preview.find { |p| p[:path_template] == "/stations" && p[:http_method] == "POST" }

      expect(post_station[:name]).to eq("Create a station")
    end

    it "falls back to 'METHOD path' when neither operationId nor summary exist" do
      preview = service.import(spec, dry_run: true)[:preview]
      obs = preview.find { |p| p[:path_template] == "/stations/{id}/observations" }

      expect(obs[:name]).to eq("GET /stations/{id}/observations")
    end

    it "derives a slug from the operationId" do
      preview = service.import(spec, dry_run: true)[:preview]
      get_stations = preview.find { |p| p[:name] == "listStations" }

      expect(get_stations[:slug]).to eq("list_stations")
    end

    it "carries provenance metadata describing the import source" do
      preview = service.import(spec, dry_run: true)[:preview]
      get_stations = preview.find { |p| p[:name] == "listStations" }

      expect(get_stations[:metadata]).to include(
        "imported_from" => "openapi",
        "operation_id" => "listStations",
        "source_path" => "/stations",
        "source_method" => "GET"
      )
    end
  end

  describe "#import — recursive $ref resolution against components" do
    it "inlines a $ref response body so no dangling pointer remains" do
      preview = service.import(spec, dry_run: true)[:preview]
      get_stations = preview.find { |p| p[:name] == "listStations" }
      schema = get_stations[:response_schema]

      # StationList -> array of Station -> {id,name,coords}; fully inlined.
      expect(schema["type"]).to eq("array")
      expect(schema).not_to have_key("$ref")
      expect(schema.dig("items", "type")).to eq("object")
      expect(schema.dig("items", "properties")).to include("id", "name", "coords")
    end

    it "resolves a $ref nested inside another resolved $ref (transitive chase)" do
      preview = service.import(spec, dry_run: true)[:preview]
      get_stations = preview.find { |p| p[:name] == "listStations" }

      coords = get_stations[:response_schema].dig("items", "properties", "coords")
      expect(coords).not_to have_key("$ref")
      expect(coords["type"]).to eq("object")
      expect(coords["properties"]).to include("lat", "lon")
    end

    it "uses the 'default' response schema when no 2xx is present" do
      preview = service.import(spec, dry_run: true)[:preview]
      obs = preview.find { |p| p[:path_template] == "/stations/{id}/observations" }

      expect(obs[:response_schema]).to eq({ "type" => "object", "properties" => { "ok" => { "type" => "boolean" } } })
    end

    it "falls back to a first-2xx response when '200' is absent" do
      preview = service.import(spec, dry_run: true)[:preview]
      post_station = preview.find { |p| p[:http_method] == "POST" }

      # The POST declares only "201"; its Station schema must still resolve.
      expect(post_station[:response_schema]["type"]).to eq("object")
      expect(post_station[:response_schema]["properties"]).to include("id")
    end

    it "returns an empty schema when an operation declares no responses" do
      bare = {
        "paths" => {
          "/ping" => { "get" => { "operationId" => "ping" } }
        }
      }
      preview = described_class.new(data_source).import(bare, dry_run: true)[:preview]

      expect(preview.first[:response_schema]).to eq({})
    end

    it "accepts a symbol-keyed spec by stringifying top-level keys" do
      sym_spec = {
        paths: {
          "/ping" => {
            "get" => {
              "operationId" => "ping",
              "responses" => {
                "200" => { "content" => { "application/json" => { "schema" => { "type" => "object" } } } }
              }
            }
          }
        }
      }
      result = described_class.new(data_source).import(sym_spec, dry_run: true)

      expect(result[:errors]).to be_empty
      expect(result[:preview].first[:slug]).to eq("ping")
    end
  end

  describe "#import — dry_run preview without persistence" do
    it "returns a preview but creates nothing and persists no rows" do
      expect do
        result = service.import(spec, dry_run: true)
        expect(result[:created]).to be_empty
        expect(result[:preview].size).to eq(3)
      end.not_to change(Ai::DataSourceEndpoint, :count)
    end

    it "defaults to a persisting import (dry_run false)" do
      expect do
        result = service.import(spec)
        expect(result[:created].size).to eq(3)
      end.to change(Ai::DataSourceEndpoint, :count).by(3)
    end
  end

  describe "#import — persisted import creates endpoints" do
    it "creates an endpoint per operation under the data source" do
      result = service.import(spec)

      expect(result[:created].size).to eq(3)
      expect(result[:errors]).to be_empty
      expect(data_source.endpoints.reload.count).to eq(3)
    end

    it "persists the resolved schema and http method on each endpoint" do
      service.import(spec)
      endpoint = data_source.endpoints.reload.find_by(slug: "list_stations")

      expect(endpoint.http_method).to eq("GET")
      expect(endpoint.path_template).to eq("/stations")
      expect(endpoint.response_schema["type"]).to eq("array")
      expect(endpoint.response_schema).not_to have_key("$ref")
    end

    it "returns serialized records (id + core attrs) for each created endpoint" do
      created = service.import(spec)[:created]
      list = created.find { |c| c[:slug] == "list_stations" }

      expect(list[:id]).to be_present
      expect(list).to include(
        name: "listStations",
        http_method: "GET",
        path_template: "/stations",
        response_format: "json"
      )
    end
  end

  describe "#import — skips duplicate slugs" do
    it "skips slugs already present on the data source (idempotent re-import)" do
      first = service.import(spec)
      expect(first[:created].size).to eq(3)

      # Second import of the same spec creates nothing new (all slugs exist) and
      # records no errors — duplicates are skipped, not reported.
      expect do
        second = service.import(spec)
        expect(second[:created]).to be_empty
        expect(second[:errors]).to be_empty
      end.not_to change(Ai::DataSourceEndpoint, :count)
    end

    it "skips a duplicate slug produced twice within the same batch" do
      colliding = {
        "paths" => {
          "/a" => { "get" => { "operationId" => "dup", "responses" => {} } },
          "/b" => { "get" => { "operationId" => "dup", "responses" => {} } }
        }
      }

      result = described_class.new(data_source).import(colliding)

      # Both operations slugify to "dup"; only the first persists.
      expect(result[:created].size).to eq(1)
      expect(result[:created].first[:slug]).to eq("dup")
      expect(data_source.endpoints.reload.where(slug: "dup").count).to eq(1)
    end
  end

  describe "#import — error handling" do
    it "reports a missing 'paths' object as an error without raising" do
      result = service.import({ "openapi" => "3.0.0" })

      expect(result[:created]).to be_empty
      expect(result[:preview]).to be_empty
      expect(result[:errors]).to include(/missing 'paths'/)
    end

    it "collects a per-path error and still imports the healthy paths" do
      # A path_item whose operation is a Hash that explodes during attr building:
      # stub operation_attrs to raise only for the bad path so the rescue in
      # build_previews records "path <p>: ..." and the other path still previews.
      allow(service).to receive(:operation_attrs).and_call_original
      allow(service).to receive(:operation_attrs)
        .with("/boom", anything, anything)
        .and_raise(StandardError, "kaboom")

      mixed = {
        "paths" => {
          "/ok" => { "get" => { "operationId" => "ok", "responses" => {} } },
          "/boom" => { "get" => { "operationId" => "boom", "responses" => {} } }
        }
      }

      result = service.import(mixed, dry_run: true)

      expect(result[:preview].map { |p| p[:slug] }).to eq(%w[ok])
      expect(result[:errors]).to include(/path \/boom: kaboom/)
    end

    it "records a save failure in errors and keeps importing the rest" do
      # Make ONE operation produce attrs with an invalid http_method so its save
      # fails validation while the others persist. The persist loop rescues per
      # attrs, so one bad row is reported in :errors but never aborts the batch.
      allow(service).to receive(:operation_attrs).and_wrap_original do |orig, path, method, operation|
        attrs = orig.call(path, method, operation)
        attrs[:http_method] = "INVALID" if attrs[:slug] == "list_stations"
        attrs
      end

      result = service.import(spec)

      expect(result[:created].size).to eq(2)
      expect(result[:created].map { |c| c[:slug] }).not_to include("list_stations")
      expect(result[:errors].size).to eq(1)
      expect(result[:errors].first).to match(/is not included|http method/i)
    end
  end
end
