# frozen_string_literal: true

require "rails_helper"

# Phase-2b drift detector. SchemaDriftService is a PURE service: #diff never
# touches the DB or network, and #record_version! only appends rows to
# ai_data_source_schema_versions. There is nothing external to stub for the diff
# path. For the persistence path we create real DataSourceEndpoint records, so we
# silence the DataSource after_commit KG sync at the bridge boundary
# (Ai::DataSourceGraph::BridgeService#sync_data_source) — under DatabaseCleaner's
# :deletion strategy that after_commit DOES fire on factory creates and would
# otherwise reach the real embedding backend / Redis (this bit Phase 2a).
#
# The CRITICAL regression guard here is array-root schema handling: QueryService
# #infer_schema emits a TOP-LEVEL array ({type:array, items:{type:object,
# properties:{...}}}) — a prior version of flatten_fields only recursed into
# array items when nested, which made drift detection on the real (array-root)
# input a permanent no-op. These specs drive #record_version! with exactly that
# shape and assert added->additive, removed->breaking, retype->breaking,
# identical->none.
RSpec.describe Ai::DataSources::SchemaDriftService, type: :service do
  subject(:service) { described_class.new }

  before do
    # Keep endpoint/source factory creates off the real embedding backend + KG
    # sync (after_commit fires under :deletion).
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # ---------------------------------------------------------------------------
  # Schema builders. OBJECT-root is the {type:object, properties:{...}} shape
  # stored on DataSourceEndpoint#response_schema; ARRAY-root is the exact shape
  # QueryService#infer_schema emits ({type:array, items:{type:object,
  # properties:{...}}}). Both must classify identically.
  # ---------------------------------------------------------------------------

  # OBJECT-root: { "type" => "object", "properties" => { field => { "type" => t } } }
  def object_schema(fields)
    {
      "type" => "object",
      "properties" => fields.transform_values { |t| { "type" => t } }
    }
  end

  # ARRAY-root: mirrors QueryService#infer_schema output verbatim.
  def array_schema(fields)
    {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => fields.transform_values { |t| { "type" => t } }
      }
    }
  end

  # ===========================================================================
  # #diff — classification across BOTH schema roots.
  #
  # Each case is asserted against object-root AND array-root inputs so the
  # array-root regression (flatten_fields not recursing at the root) can never
  # silently return. shared_examples keeps the matrix DRY while still emitting a
  # distinct example per root.
  # ===========================================================================
  describe "#diff" do
    shared_examples "drift classification" do |build|
      it "classifies a pure field addition as additive" do
        old = build.call("city" => "string")
        new = build.call("city" => "string", "temp" => "number")

        result = service.diff(old, new)

        expect(result[:classification]).to eq(described_class::ADDITIVE)
        expect(result[:added_fields]).to include(a_string_matching(/temp/))
        expect(result[:removed_fields]).to be_empty
        expect(result[:type_changes]).to be_empty
      end

      it "classifies a field removal as breaking" do
        old = build.call("city" => "string", "temp" => "number")
        new = build.call("city" => "string")

        result = service.diff(old, new)

        expect(result[:classification]).to eq(described_class::BREAKING)
        expect(result[:removed_fields]).to include(a_string_matching(/temp/))
        expect(result[:added_fields]).to be_empty
        expect(result[:type_changes]).to be_empty
      end

      it "classifies a type change on an existing field as breaking" do
        old = build.call("temp" => "number")
        new = build.call("temp" => "string")

        result = service.diff(old, new)

        expect(result[:classification]).to eq(described_class::BREAKING)
        expect(result[:type_changes]).to contain_exactly(
          a_hash_including(from: "number", to: "string")
        )
        expect(result[:added_fields]).to be_empty
        expect(result[:removed_fields]).to be_empty
      end

      it "classifies structurally identical schemas as none" do
        old = build.call("city" => "string", "temp" => "number")
        new = build.call("city" => "string", "temp" => "number")

        result = service.diff(old, new)

        expect(result[:classification]).to eq(described_class::NONE)
        expect(result[:added_fields]).to be_empty
        expect(result[:removed_fields]).to be_empty
        expect(result[:type_changes]).to be_empty
      end
    end

    # Build schemas INLINE in the lambdas (not via the instance helpers) so the
    # builder has no dependency on example-instance methods — include_examples
    # evaluates the lambda at example-GROUP scope where instance helpers are absent.
    context "with OBJECT-root schemas" do
      include_examples "drift classification", ->(fields) {
        { "type" => "object", "properties" => fields.transform_values { |t| { "type" => t } } }
      }
    end

    context "with ARRAY-root schemas (QueryService#infer_schema shape)" do
      include_examples "drift classification", ->(fields) {
        { "type" => "array",
          "items" => { "type" => "object", "properties" => fields.transform_values { |t| { "type" => t } } } }
      }
    end

    context "with no prior schema" do
      it "classifies a nil old schema as initial" do
        result = service.diff(nil, array_schema("city" => "string"))

        expect(result[:classification]).to eq(described_class::INITIAL)
        # On a first version every field is technically "added" but that is not
        # drift — the classification is initial, not additive.
        expect(result[:added_fields]).to include(a_string_matching(/city/))
      end

      it "classifies an empty-hash old schema as initial" do
        result = service.diff({}, object_schema("city" => "string"))

        expect(result[:classification]).to eq(described_class::INITIAL)
      end
    end

    context "when additions and a breaking change happen together" do
      it "classifies as breaking (removal wins over the concurrent addition)" do
        old = array_schema("city" => "string", "temp" => "number")
        new = array_schema("city" => "string", "humidity" => "integer")

        result = service.diff(old, new)

        expect(result[:classification]).to eq(described_class::BREAKING)
        expect(result[:added_fields]).to include(a_string_matching(/humidity/))
        expect(result[:removed_fields]).to include(a_string_matching(/temp/))
      end
    end
  end

  # ===========================================================================
  # #record_version! — sequential versioning, persistence, idempotency.
  # Driven with array-root (infer_schema-shaped) schemas, the real production
  # input, so the persisted classification reflects the array-root code path.
  # ===========================================================================
  describe "#record_version!" do
    let(:account) { create(:account) }
    let(:data_source) { create(:ai_data_source, account: account, source_type: "open_meteo") }
    let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

    it "raises ArgumentError when the endpoint is nil" do
      expect { service.record_version!(nil, array_schema("city" => "string")) }
        .to raise_error(ArgumentError, /endpoint is required/)
    end

    it "creates version 1 with classification initial for the first snapshot" do
      version = nil
      expect { version = service.record_version!(endpoint, array_schema("city" => "string")) }
        .to change { endpoint.schema_versions.count }.from(0).to(1)

      expect(version).to be_persisted
      expect(version.version).to eq(1)
      expect(version.classification).to eq(described_class::INITIAL)
      expect(version.checksum).to be_present
    end

    it "assigns sequential version numbers across successive distinct snapshots" do
      v1 = service.record_version!(endpoint, array_schema("city" => "string"))
      v2 = service.record_version!(endpoint, array_schema("city" => "string", "temp" => "number"))
      v3 = service.record_version!(endpoint, array_schema("city" => "string"))

      expect([v1.version, v2.version, v3.version]).to eq([1, 2, 3])
      expect(endpoint.schema_versions.count).to eq(3)
    end

    it "persists the classification and structural diff for an additive change" do
      service.record_version!(endpoint, array_schema("city" => "string"))
      v2 = service.record_version!(endpoint, array_schema("city" => "string", "temp" => "number"))

      expect(v2.classification).to eq(described_class::ADDITIVE)
      expect(v2.diff["added_fields"]).to include(a_string_matching(/temp/))
      expect(v2.diff["removed_fields"]).to eq([])
      expect(v2.diff["type_changes"]).to eq([])
    end

    it "records a breaking classification when a field is removed" do
      service.record_version!(endpoint, array_schema("city" => "string", "temp" => "number"))
      v2 = service.record_version!(endpoint, array_schema("city" => "string"))

      expect(v2.classification).to eq(described_class::BREAKING)
      expect(v2.diff["removed_fields"]).to include(a_string_matching(/temp/))
    end

    it "records a breaking classification when an existing field changes type" do
      service.record_version!(endpoint, array_schema("temp" => "number"))
      v2 = service.record_version!(endpoint, array_schema("temp" => "string"))

      expect(v2.classification).to eq(described_class::BREAKING)
      type_change = v2.diff["type_changes"].first
      expect(type_change).to include("from" => "number", "to" => "string")
    end

    it "stores the snapshotted schema on the persisted version" do
      schema = array_schema("city" => "string", "temp" => "number")
      version = service.record_version!(endpoint, schema)

      expect(version.schema).to eq(schema.deep_stringify_keys)
    end

    describe "idempotency on an unchanged checksum" do
      it "returns the existing latest version without creating a new row" do
        schema = array_schema("city" => "string")
        first = service.record_version!(endpoint, schema)

        second = nil
        expect { second = service.record_version!(endpoint, schema) }
          .not_to change { endpoint.schema_versions.count }

        expect(second.id).to eq(first.id)
        expect(second.version).to eq(first.version)
      end

      it "reports classification none for the repeat call (nothing drifted)" do
        schema = array_schema("city" => "string", "temp" => "number")
        service.record_version!(endpoint, schema)

        repeat = service.record_version!(endpoint, schema)

        expect(repeat.classification).to eq(described_class::NONE)
      end

      it "treats a symbol-keyed schema as identical to its string-keyed twin (checksum-stable)" do
        service.record_version!(endpoint, { "type" => "array",
                                            "items" => { "type" => "object",
                                                         "properties" => { "city" => { "type" => "string" } } } })

        symbol_keyed = { type: "array",
                         items: { type: "object", properties: { city: { type: "string" } } } }

        expect { service.record_version!(endpoint, symbol_keyed) }
          .not_to change { endpoint.schema_versions.count }
      end

      it "appends a fresh version once the schema changes again after a no-op repeat" do
        base = array_schema("city" => "string")
        service.record_version!(endpoint, base)        # v1 initial
        service.record_version!(endpoint, base)        # no-op (none)
        v2 = service.record_version!(endpoint, array_schema("city" => "string", "temp" => "number"))

        expect(v2.version).to eq(2)
        expect(v2.classification).to eq(described_class::ADDITIVE)
        expect(endpoint.schema_versions.count).to eq(2)
      end
    end
  end
end
