# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::IncrementalSync is the pure cursor-plumbing module for the
# Phase-5 incremental pull loop. It is stateless: no DB, no Redis, no network —
# just dotted-path digging over plain Ruby Hashes/Arrays/Strings — so this spec
# needs neither factories nor a database. Every example is built from literal
# hashes and strings.
#
# Public surface (all via module_function, called as IncrementalSync.foo):
#   .apply_cursor(params, incremental_config, cursor)  -> params copy
#   .extract_cursor(envelope, incremental_config)      -> next_cursor | nil
#   .cursor_from_body(raw_body, incremental_config)    -> next_cursor | nil
RSpec.describe Ai::DataSources::IncrementalSync do
  # ==========================================================================
  # .apply_cursor — stamp the high-watermark onto the OUTBOUND fetch params.
  # ==========================================================================
  describe ".apply_cursor" do
    let(:config) { { "cursor_param" => "since", "cursor_path" => "provenance.next" } }

    context "when a cursor_param and a non-blank cursor are both present" do
      it "stamps the cursor onto a COPY under the configured cursor_param" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, config, "2026-01-01T00:00:00Z")

        expect(result).to eq(
          "category" => "weather",
          "since" => "2026-01-01T00:00:00Z"
        )
      end

      it "does NOT mutate the caller's params hash" do
        params = { "category" => "weather" }

        described_class.apply_cursor(params, config, "CUR")

        expect(params).to eq("category" => "weather")
        expect(params).not_to have_key("since")
      end

      it "returns a different object than the one passed in" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, config, "CUR")

        expect(result).not_to equal(params)
      end

      it "composes the string-keyed cursor with a string-keyed param map" do
        params = { "limit" => "50", "order" => "asc" }

        result = described_class.apply_cursor(params, config, "tok-7")

        expect(result).to eq(
          "limit" => "50",
          "order" => "asc",
          "since" => "tok-7"
        )
        # the stamped key is the string "since", not a symbol
        expect(result.keys).to include("since")
        expect(result).not_to have_key(:since)
      end

      it "overwrites any pre-existing value already sitting under cursor_param" do
        params = { "since" => "STALE" }

        result = described_class.apply_cursor(params, config, "FRESH")

        expect(result["since"]).to eq("FRESH")
      end

      it "reads cursor_param from a symbol-keyed config too" do
        result = described_class.apply_cursor({ "a" => 1 }, { cursor_param: "after" }, "X")

        expect(result).to eq("a" => 1, "after" => "X")
      end
    end

    context "when the cursor is blank" do
      it "returns an unchanged copy for a nil cursor" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, config, nil)

        expect(result).to eq("category" => "weather")
        expect(result).not_to have_key("since")
        expect(result).not_to equal(params)
      end

      it "returns an unchanged copy for an empty-string cursor" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, config, "")

        expect(result).to eq("category" => "weather")
        expect(result).not_to have_key("since")
      end

      it "returns an unchanged copy for a whitespace-only cursor (blank?)" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, config, "   ")

        expect(result).to eq("category" => "weather")
        expect(result).not_to have_key("since")
      end
    end

    context "when the incremental config lacks a cursor_param" do
      it "returns an unchanged copy when cursor_param is absent" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, { "cursor_path" => "x.y" }, "CUR")

        expect(result).to eq("category" => "weather")
        expect(result).not_to equal(params)
      end

      it "returns an unchanged copy when cursor_param is blank/whitespace" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, { "cursor_param" => "  " }, "CUR")

        expect(result).to eq("category" => "weather")
      end

      it "returns an unchanged copy when the config is not a Hash" do
        params = { "category" => "weather" }

        result = described_class.apply_cursor(params, nil, "CUR")

        expect(result).to eq("category" => "weather")
      end
    end

    context "when params is nil" do
      it "treats nil params as an empty hash and still stamps the cursor" do
        result = described_class.apply_cursor(nil, config, "CUR")

        expect(result).to eq("since" => "CUR")
      end

      it "returns an empty hash for nil params + blank cursor" do
        result = described_class.apply_cursor(nil, config, nil)

        expect(result).to eq({})
      end
    end
  end

  # ==========================================================================
  # .extract_cursor — pull the NEXT watermark out of a completed FetchEnvelope.
  # ==========================================================================
  describe ".extract_cursor" do
    let(:config) { { "cursor_path" => "0.updated_at" } }

    context "when the envelope is not a Hash" do
      it "returns nil for nil" do
        expect(described_class.extract_cursor(nil, config)).to be_nil
      end

      it "returns nil for an Array" do
        expect(described_class.extract_cursor([{ "updated_at" => "t1" }], config)).to be_nil
      end

      it "returns nil for a String" do
        expect(described_class.extract_cursor("not-an-envelope", config)).to be_nil
      end
    end

    context "when provenance carries a pre-dug incremental_cursor" do
      it "PREFERS provenance[\"incremental_cursor\"] over the configured cursor_path" do
        envelope = {
          provenance: { "incremental_cursor" => "PROV-WINS" },
          data: [{ "updated_at" => "RECORD-LOSES" }]
        }

        # cursor_path "0.updated_at" would resolve to RECORD-LOSES against data,
        # but the pre-dug provenance cursor must win.
        expect(described_class.extract_cursor(envelope, config)).to eq("PROV-WINS")
      end

      it "wins even when cursor_path is blank (the path is never consulted)" do
        envelope = { provenance: { "incremental_cursor" => "PROV" }, data: [] }

        expect(described_class.extract_cursor(envelope, {})).to eq("PROV")
      end

      it "reads the pre-dug cursor from a symbol-keyed provenance hash" do
        envelope = { provenance: { incremental_cursor: "SYM-PROV" }, data: [] }

        expect(described_class.extract_cursor(envelope, config)).to eq("SYM-PROV")
      end

      it "reads the pre-dug cursor when provenance is under the string \"provenance\" key" do
        envelope = { "provenance" => { "incremental_cursor" => "STR-PROV" }, "data" => [] }

        expect(described_class.extract_cursor(envelope, config)).to eq("STR-PROV")
      end

      it "stringifies a numeric pre-dug cursor" do
        envelope = { provenance: { "incremental_cursor" => 12_345 }, data: [] }

        expect(described_class.extract_cursor(envelope, config)).to eq("12345")
      end

      it "does NOT prefer a blank pre-dug cursor — falls through to the path" do
        envelope = {
          provenance: { "incremental_cursor" => "" },
          data: [{ "updated_at" => "FROM-DATA" }]
        }

        # "" is blank? so the provenance pre-dug branch is skipped and the
        # configured path resolves against the records instead.
        expect(described_class.extract_cursor(envelope, config)).to eq("FROM-DATA")
      end

      it "returns nil (does NOT fall through) when the pre-dug cursor is a container" do
        # A Hash is present? but not a valid scalar cursor: normalize_cursor(pre)
        # is returned immediately, so the path fallback is never reached.
        envelope = {
          provenance: { "incremental_cursor" => { "nested" => "x" } },
          data: [{ "updated_at" => "WOULD-BE-DATA" }]
        }

        expect(described_class.extract_cursor(envelope, config)).to be_nil
      end
    end

    context "when falling back to the configured cursor_path" do
      it "digs a nested paging token out of provenance (path is relative: paging.next)" do
        envelope = {
          provenance: { "paging" => { "next" => "PAGE-2" } },
          data: [{ "updated_at" => "t9" }]
        }

        # cursor_path is RELATIVE to the provenance hash — NOT prefixed with
        # "provenance." (the path is dug against provenance directly).
        result = described_class.extract_cursor(envelope, { "cursor_path" => "paging.next" })

        expect(result).to eq("PAGE-2")
      end

      it "digs a record-embedded cursor out of the canonical records (0.updated_at)" do
        envelope = {
          provenance: {},
          data: [{ "updated_at" => "t1" }, { "updated_at" => "t2" }]
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "0.updated_at" })).to eq("t1")
      end

      it "digs the LAST record's cursor with a negative index (-1.updated_at)" do
        envelope = {
          provenance: {},
          data: [{ "updated_at" => "t1" }, { "updated_at" => "t2" }, { "updated_at" => "t3" }]
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "-1.updated_at" })).to eq("t3")
      end

      it "prefers provenance over data when BOTH resolve the same path" do
        # cursor_path "next" resolves on provenance AND on data — provenance wins.
        envelope = {
          provenance: { "next" => "FROM-PROV" },
          data: { "next" => "FROM-DATA" }
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "next" })).to eq("FROM-PROV")
      end

      it "falls through to data when the path is absent in provenance" do
        envelope = {
          provenance: { "unrelated" => "z" },
          data: { "next" => "FROM-DATA" }
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "next" })).to eq("FROM-DATA")
      end

      it "reads provenance/data under string keys as well as symbol keys" do
        envelope = {
          "provenance" => { "next" => "STR-PROV" },
          "data" => []
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "next" })).to eq("STR-PROV")
      end

      it "tolerates symbol-keyed hops along the path" do
        envelope = {
          provenance: { paging: { next: "DEEP" } },
          data: []
        }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "paging.next" })).to eq("DEEP")
      end

      it "reads cursor_path from a symbol-keyed config" do
        envelope = { provenance: { "next" => "OK" }, data: [] }

        expect(described_class.extract_cursor(envelope, { cursor_path: "next" })).to eq("OK")
      end
    end

    context "when the path resolves to nothing" do
      it "returns nil when cursor_path is blank and there is no pre-dug cursor" do
        envelope = { provenance: {}, data: [{ "updated_at" => "t1" }] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "" })).to be_nil
      end

      it "returns nil when the config has no cursor_path at all" do
        envelope = { provenance: {}, data: [{ "updated_at" => "t1" }] }

        expect(described_class.extract_cursor(envelope, {})).to be_nil
      end

      it "returns nil when the path misses in both provenance and data" do
        envelope = { provenance: { "a" => 1 }, data: [{ "b" => 2 }] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "nope.gone" })).to be_nil
      end

      it "returns nil when the data is an empty array and provenance lacks the path" do
        envelope = { provenance: {}, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "0.updated_at" })).to be_nil
      end
    end

    context "with malformed / dotted paths (graceful degradation, never raises)" do
      it "drops blank inner segments so \"a..b\" digs a -> b" do
        envelope = { provenance: { "a" => { "b" => "DEEP" } }, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "a..b" })).to eq("DEEP")
      end

      it "drops a trailing dot so \"a.\" digs just a" do
        envelope = { provenance: { "a" => "VAL" }, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "a." })).to eq("VAL")
      end

      it "treats a path of only dots as empty and returns nil" do
        envelope = { provenance: { "a" => "VAL" }, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "..." })).to be_nil
      end
    end

    context "with array index edge cases" do
      it "resolves a non-numeric segment against an Array to nil (no raise)" do
        envelope = { provenance: {}, data: [{ "updated_at" => "t1" }] }

        expect do
          @result = described_class.extract_cursor(envelope, { "cursor_path" => "foo.updated_at" })
        end.not_to raise_error
        expect(@result).to be_nil
      end

      it "resolves an out-of-bounds index to nil" do
        envelope = { provenance: {}, data: [{ "updated_at" => "t1" }] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "9.updated_at" })).to be_nil
      end
    end

    context "with non-scalar values at the resolved path (normalize_cursor rejects containers)" do
      it "returns nil when the path resolves to a Hash" do
        envelope = { provenance: { "next" => { "deep" => "x" } }, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "next" })).to be_nil
      end

      it "returns nil when the path resolves to an Array" do
        envelope = { provenance: { "next" => %w[a b] }, data: [] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "next" })).to be_nil
      end

      it "stringifies a numeric scalar cursor pulled from the records" do
        envelope = { provenance: {}, data: [{ "seq" => 42 }] }

        expect(described_class.extract_cursor(envelope, { "cursor_path" => "0.seq" })).to eq("42")
      end
    end

    context "deep nesting" do
      it "walks several hops through mixed hash/array nodes" do
        envelope = {
          provenance: {
            "paging" => {
              "cursors" => [{ "token" => "T0" }, { "token" => "T1" }]
            }
          },
          data: []
        }

        result = described_class.extract_cursor(
          envelope, { "cursor_path" => "paging.cursors.-1.token" }
        )

        expect(result).to eq("T1")
      end
    end
  end

  # ==========================================================================
  # .cursor_from_body — dig the NEXT cursor out of the RAW (pre-unwrap) body.
  # ==========================================================================
  describe ".cursor_from_body" do
    context "happy path" do
      it "parses the raw JSON string and digs the top-level paging token" do
        raw = '{"meta":{"next_cursor":"abc"},"items":[]}'

        result = described_class.cursor_from_body(raw, { "cursor_path" => "meta.next_cursor" })

        expect(result).to eq("abc")
      end

      it "reaches a token the records-unwrap would otherwise discard" do
        # items[] is what becomes the canonical records; the cursor lives OUTSIDE
        # it, so only a raw-body dig can recover it.
        raw = '{"data":[{"id":1},{"id":2}],"next":"PAGE-2"}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "next" })).to eq("PAGE-2")
      end

      it "stringifies a numeric value at the path" do
        raw = '{"meta":{"offset":300}}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "meta.offset" })).to eq("300")
      end

      it "reads cursor_path from a symbol-keyed config" do
        raw = '{"meta":{"next":"sym"}}'

        expect(described_class.cursor_from_body(raw, { cursor_path: "meta.next" })).to eq("sym")
      end

      it "digs into a JSON array body with an index path" do
        raw = '[{"updated_at":"t1"},{"updated_at":"t2"}]'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "-1.updated_at" })).to eq("t2")
      end
    end

    context "blank inputs" do
      it "returns nil for a nil raw_body" do
        expect(described_class.cursor_from_body(nil, { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil for an empty raw_body" do
        expect(described_class.cursor_from_body("", { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil for a whitespace-only raw_body" do
        expect(described_class.cursor_from_body("   ", { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil for a blank cursor_path" do
        expect(described_class.cursor_from_body('{"meta":{"next":"x"}}', { "cursor_path" => "" })).to be_nil
      end

      it "returns nil when the config has no cursor_path" do
        expect(described_class.cursor_from_body('{"meta":{"next":"x"}}', {})).to be_nil
      end

      it "returns nil when the config is not a Hash" do
        expect(described_class.cursor_from_body('{"meta":{"next":"x"}}', nil)).to be_nil
      end
    end

    context "non-JSON / malformed bodies (rescued, never raises)" do
      it "returns nil for a non-JSON garbage body without raising" do
        expect do
          @result = described_class.cursor_from_body("this is not json", { "cursor_path" => "meta.next" })
        end.not_to raise_error
        expect(@result).to be_nil
      end

      it "returns nil for truncated JSON" do
        expect(described_class.cursor_from_body('{"meta":{"next":', { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil for a JSON scalar body that cannot be dug" do
        # valid JSON, but a bare number is neither Hash nor Array, so the dig
        # bottoms out at nil rather than raising.
        expect(described_class.cursor_from_body("42", { "cursor_path" => "meta.next" })).to be_nil
      end
    end

    context "path absent in the parsed body" do
      it "returns nil when the dotted path is missing" do
        raw = '{"meta":{"other":"x"},"items":[]}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "meta.next_cursor" })).to be_nil
      end

      it "returns nil when an intermediate hop is missing" do
        raw = '{"top":"scalar"}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "top.deeper" })).to be_nil
      end

      it "returns nil when the path resolves to a JSON null" do
        raw = '{"meta":{"next":null}}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil when the path resolves to a JSON object (container rejected)" do
        raw = '{"meta":{"next":{"nested":1}}}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "meta.next" })).to be_nil
      end

      it "returns nil when the path resolves to a JSON array (container rejected)" do
        raw = '{"meta":{"next":[1,2]}}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "meta.next" })).to be_nil
      end

      it "tolerates dotted/malformed paths against a parsed body" do
        raw = '{"a":{"b":"DEEP"}}'

        expect(described_class.cursor_from_body(raw, { "cursor_path" => "a..b" })).to eq("DEEP")
      end
    end
  end
end
