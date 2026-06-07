# frozen_string_literal: true

require "digest"

module Ai
  module DataSources
    # Detects and records response-schema drift for a data-source endpoint.
    #
    # CONTRACT:
    #   Ai::DataSources::SchemaDriftService.new(account = nil)
    #     #diff(old_schema, new_schema) =>
    #       { classification:, added_fields: [], removed_fields: [], type_changes: [] }
    #     #record_version!(endpoint, schema) => Ai::DataSourceSchemaVersion
    #
    # Classification semantics (vs the immediately prior version):
    #   initial  : no prior schema (old_schema blank)
    #   none     : structurally identical
    #   additive : fields were added and none removed/retyped. For the CONSUME
    #              direction (we read external APIs) extra response fields are
    #              always backward compatible, so any pure addition is additive;
    #              the JSON-Schema "required" array is not consulted.
    #   breaking : a field was removed OR an existing field changed type
    #
    # Schemas are JSON-Schema-shaped Hashes (the same shape stored on
    # DataSourceEndpoint#response_schema): an object with "properties" and an
    # optional "required" array, possibly nested. Field comparison is done on the
    # flattened dotted property paths and their declared "type", so nested objects
    # and array item schemas are compared structurally rather than by raw equality.
    class SchemaDriftService
      # Diff classifications, mirrored from the model so callers can branch on
      # SchemaDriftService::BREAKING without reaching into the AR class.
      INITIAL  = "initial"
      NONE     = "none"
      ADDITIVE = "additive"
      BREAKING = "breaking"

      def initialize(account = nil)
        @account = account
      end

      # Pure structural diff of two schemas. Never persists. Nil/blank old_schema
      # yields an :initial classification (every field is "added" but additions on
      # a first version are not drift).
      def diff(old_schema, new_schema)
        old_fields = flatten_fields(old_schema)
        new_fields = flatten_fields(new_schema)

        added = (new_fields.keys - old_fields.keys).sort
        removed = (old_fields.keys - new_fields.keys).sort

        type_changes = (old_fields.keys & new_fields.keys).filter_map do |path|
          before = old_fields[path]
          after = new_fields[path]
          next if before == after || before.nil? || after.nil?

          { field: path, from: before, to: after }
        end

        {
          classification: classify(old_schema, added, removed, type_changes),
          added_fields: added,
          removed_fields: removed,
          type_changes: type_changes
        }
      end

      # Diff the supplied schema against the endpoint's latest recorded version,
      # classify, and persist the next version. Idempotent: when the schema is
      # byte-identical (same checksum) to the latest version, NO new row is created
      # and the existing latest version is returned with classification "none".
      #
      # Returns the persisted (or existing latest) Ai::DataSourceSchemaVersion.
      def record_version!(endpoint, schema)
        raise ArgumentError, "endpoint is required" if endpoint.nil?

        normalized = normalize_schema(schema)
        checksum = checksum_for(normalized)
        latest = latest_version_for(endpoint)

        # Idempotency: identical schema to the latest snapshot -> no-op append.
        # Per contract, the returned version must report classification "none" for
        # THIS call (nothing drifted), so consumers that branch on the returned
        # token (e.g. QueryService, which re-emits a "breaking" signal and flags an
        # anomaly whenever the token != "none") correctly see no change on repeat
        # polls of an unchanged schema. The override is in-memory ONLY: we mark the
        # record readonly so an accidental save can never write "none" back over the
        # version's true recorded classification, keeping the audit history intact.
        if latest && latest.checksum == checksum
          latest.classification = NONE
          latest.readonly! if latest.respond_to?(:readonly!)
          return latest
        end

        result = diff(latest&.schema, normalized)
        next_number = (latest&.version || 0) + 1

        Ai::DataSourceSchemaVersion.create!(
          endpoint: endpoint,
          version: next_number,
          schema: normalized,
          checksum: checksum,
          classification: result[:classification],
          diff: {
            "added_fields" => result[:added_fields],
            "removed_fields" => result[:removed_fields],
            "type_changes" => result[:type_changes]
          }
        )
      end

      private

      attr_reader :account

      # Pick the highest-version row for the endpoint. Uses the association when
      # the endpoint is a persisted record; falls back to a scoped query otherwise.
      def latest_version_for(endpoint)
        Ai::DataSourceSchemaVersion.for_endpoint(endpoint).latest_first.first
      end

      # Decide the classification from the structural deltas. Order matters:
      # a removal or type change is breaking even if additions also happened.
      def classify(old_schema, added, removed, type_changes)
        return INITIAL if old_schema.blank?
        return BREAKING if removed.any? || type_changes.any?
        return ADDITIVE if added.any?

        NONE
      end

      # Flatten a JSON-Schema-shaped Hash into { "dotted.path" => "type" }.
      # Handles nested "properties" and array "items" (suffix "[]"). Unknown or
      # missing types are recorded as "any" so two untyped fields compare equal.
      def flatten_fields(schema, prefix = "", acc = {})
        return acc unless schema.is_a?(Hash)

        props = schema["properties"] || schema[:properties]
        if props.is_a?(Hash)
          props.each do |name, subschema|
            path = prefix.empty? ? name.to_s : "#{prefix}.#{name}"
            record_field(path, subschema, acc)
          end
        end

        # Array schema (items describe each element). Must recurse at the ROOT too:
        # QueryService#infer_schema emits a top-level array ({type:array, items:{...}}),
        # so guarding on a non-empty prefix made drift detection a permanent no-op.
        items = schema["items"] || schema[:items]
        if items.is_a?(Hash)
          flatten_fields(items, prefix.empty? ? "[]" : "#{prefix}[]", acc)
        end

        acc
      end

      def record_field(path, subschema, acc)
        if subschema.is_a?(Hash)
          acc[path] = type_token(subschema)
          nested_props = subschema["properties"] || subschema[:properties]
          flatten_fields(subschema, path, acc) if nested_props.is_a?(Hash)

          items = subschema["items"] || subschema[:items]
          flatten_fields(items, "#{path}[]", acc) if items.is_a?(Hash)
        else
          acc[path] = "any"
        end
      end

      # Normalize a declared "type" to a comparable token. Arrays of types
      # (JSON Schema union) are sorted+joined so order does not register as drift.
      def type_token(subschema)
        type = subschema["type"] || subschema[:type]
        case type
        when Array then type.map(&:to_s).sort.join("|")
        when nil then "any"
        else type.to_s
        end
      end

      # Coerce to a plain Hash with string keys (so a symbol-keyed schema and its
      # JSON round-trip checksum identically).
      def normalize_schema(schema)
        return {} if schema.blank?
        return schema.deep_stringify_keys if schema.is_a?(Hash)

        {}
      end

      def checksum_for(normalized)
        Digest::SHA256.hexdigest(canonical_json(normalized))
      end

      def canonical_json(obj)
        deep_sort(obj).to_json
      rescue StandardError
        obj.to_s
      end

      def deep_sort(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }.sort.to_h
        when Array then obj.map { |v| deep_sort(v) }
        else obj
        end
      end
    end
  end
end
