# frozen_string_literal: true

require "rails_helper"

# Pure / stateless service: no DB, Redis, or network. These specs operate on
# plain Ruby hashes/arrays — no factories needed.
#
# Contract reminders gleaned from the source:
#   - A step's outer "op" selects the PIPELINE op (flatten/unnest/select/rename/
#     computed). To reach the computed interpreter the outer "op" must literally
#     be "computed"; the INNER computed op is then read from "fn"/"operation"/
#     "compute" (see #computed_op_for). That is the shape these specs use.
#   - #apply is fully rescued and never raises; malformed steps are skipped.
RSpec.describe Ai::DataSources::TransformService, type: :service do
  # Convenience: build a service whose pipeline is the given steps.
  def transform(steps, records)
    described_class.new("pipeline" => Array(steps)).apply(records)
  end

  # Convenience: build a single computed step (outer op "computed", inner via fn).
  def computed_step(fn, **rest)
    { "op" => "computed", "fn" => fn }.merge(rest.transform_keys(&:to_s))
  end

  # ---------------------------------------------------------------------------
  # PASSTHROUGH
  # ---------------------------------------------------------------------------
  describe "passthrough (no effective pipeline)" do
    let(:records) { [{ "a" => 1 }, { "b" => 2 }] }

    it "returns records unchanged for a blank config {}" do
      result = described_class.new({}).apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged for a nil config" do
      result = described_class.new(nil).apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged for a non-Hash config (String)" do
      result = described_class.new("not a hash").apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged for a non-Hash config (Array)" do
      result = described_class.new([1, 2, 3]).apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged when there is no 'pipeline' key" do
      result = described_class.new("something_else" => true).apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged for an empty pipeline []" do
      result = described_class.new("pipeline" => []).apply(records)
      expect(result).to eq(records)
    end

    it "returns records unchanged when 'pipeline' is not an Array" do
      result = described_class.new("pipeline" => "nope").apply(records)
      expect(result).to eq(records)
    end

    it "reports enabled? false for a passthrough config" do
      expect(described_class.new({}).enabled?).to be(false)
      expect(described_class.new("pipeline" => []).enabled?).to be(false)
    end

    it "reports enabled? true when a real step is present" do
      expect(described_class.new("pipeline" => [{ "op" => "flatten" }]).enabled?).to be(true)
    end

    it "coerces a non-Array records argument via Array() on passthrough" do
      # A bare Hash becomes a one-element array under Array().
      result = described_class.new({}).apply({ "a" => 1 })
      expect(result).to eq([{ "a" => 1 }])
    end

    it "coerces nil records to [] on passthrough" do
      expect(described_class.new({}).apply(nil)).to eq([])
    end

    it "tolerates symbol-keyed top-level config (deep_stringify)" do
      # Symbol-keyed config still resolves the pipeline.
      service = described_class.new(pipeline: [{ op: "select", fields: ["a"] }])
      expect(service.apply([{ "a" => 1, "b" => 2 }])).to eq([{ "a" => 1 }])
    end
  end

  # ---------------------------------------------------------------------------
  # FLATTEN
  # ---------------------------------------------------------------------------
  describe "flatten" do
    it "flattens a nested hash to dotted keys" do
      result = transform([{ "op" => "flatten" }], [{ "a" => { "b" => 1 } }])
      expect(result).to eq([{ "a.b" => 1 }])
    end

    it "flattens multiple levels of nesting" do
      result = transform([{ "op" => "flatten" }], [{ "a" => { "b" => { "c" => 9 } } }])
      expect(result).to eq([{ "a.b.c" => 9 }])
    end

    it "honors a custom separator" do
      result = transform(
        [{ "op" => "flatten", "separator" => "__" }],
        [{ "a" => { "b" => 1 } }]
      )
      expect(result).to eq([{ "a__b" => 1 }])
    end

    it "leaves non-hash values as-is" do
      result = transform([{ "op" => "flatten" }], [{ "a" => 1, "b" => [1, 2], "c" => "x" }])
      expect(result).to eq([{ "a" => 1, "b" => [1, 2], "c" => "x" }])
    end

    it "scopes descent with 'only' (other hashes left intact)" do
      result = transform(
        [{ "op" => "flatten", "only" => ["a"] }],
        [{ "a" => { "b" => 1 }, "c" => { "d" => 2 } }]
      )
      expect(result).to eq([{ "a.b" => 1, "c" => { "d" => 2 } }])
    end

    it "scopes descent with 'except' (excluded hash left intact)" do
      result = transform(
        [{ "op" => "flatten", "except" => ["c"] }],
        [{ "a" => { "b" => 1 }, "c" => { "d" => 2 } }]
      )
      expect(result).to eq([{ "a.b" => 1, "c" => { "d" => 2 } }])
    end

    it "stringifies symbol keys while flattening" do
      result = transform([{ "op" => "flatten" }], [{ a: { b: 1 }, c: 2 }])
      expect(result).to eq([{ "a.b" => 1, "c" => 2 }])
    end

    it "treats an empty nested hash as a terminal value" do
      result = transform([{ "op" => "flatten" }], [{ "a" => {} }])
      expect(result).to eq([{ "a" => {} }])
    end

    it "passes non-Hash records through unchanged" do
      result = transform([{ "op" => "flatten" }], [{ "a" => { "b" => 1 } }, "raw", 7])
      expect(result).to eq([{ "a.b" => 1 }, "raw", 7])
    end

    it "respects the MAX_FLATTEN_DEPTH cap without raising SystemStackError" do
      # Stub the cap small (3) and build a hash deeper than that. At the cap the
      # remaining subtree is written as a terminal value rather than descended.
      stub_const("Ai::DataSources::TransformService::MAX_FLATTEN_DEPTH", 3)

      record = { "l0" => { "l1" => { "l2" => { "l3" => { "l4" => "deep" } } } } }

      result = nil
      expect { result = transform([{ "op" => "flatten" }], [record]) }.not_to raise_error

      out = result.first
      # Descent stops once depth reaches the cap; the remaining subtree is kept
      # whole under the dotted prefix accumulated up to that point.
      expect(out.keys.size).to eq(1)
      key = out.keys.first
      expect(key).to start_with("l0.l1.l2")
      expect(out[key]).to be_a(Hash)
      # The terminal subtree still contains the deepest leaf.
      expect(out[key].to_s).to include("deep")
    end

    it "does not raise on a pathologically deep hash even with the default cap" do
      # Build a hash deeper than the default MAX_FLATTEN_DEPTH (32).
      deep = "leaf"
      60.times { |i| deep = { "k#{i}" => deep } }

      expect { transform([{ "op" => "flatten" }], [deep]) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # UNNEST / EXPLODE
  # ---------------------------------------------------------------------------
  describe "unnest / explode" do
    it "emits one record per array element, merging hash elements over parent fields" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1, "items" => [{ "sku" => "a" }, { "sku" => "b" }] }]
      )
      expect(result).to eq([
                             { "id" => 1, "sku" => "a" },
                             { "id" => 1, "sku" => "b" }
                           ])
    end

    it "supports the 'explode' alias" do
      result = transform(
        [{ "op" => "explode", "field" => "items" }],
        [{ "id" => 1, "items" => [{ "sku" => "a" }] }]
      )
      expect(result).to eq([{ "id" => 1, "sku" => "a" }])
    end

    it "lets element fields WIN over the parent's other fields on key collision" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1, "tag" => "parent", "items" => [{ "tag" => "child" }] }]
      )
      expect(result).to eq([{ "id" => 1, "tag" => "child" }])
    end

    it "places scalar elements under the default 'value' key" do
      result = transform(
        [{ "op" => "unnest", "field" => "nums" }],
        [{ "id" => 1, "nums" => [10, 20] }]
      )
      expect(result).to eq([
                             { "id" => 1, "value" => 10 },
                             { "id" => 1, "value" => 20 }
                           ])
    end

    it "places scalar elements under a custom 'value_key'" do
      result = transform(
        [{ "op" => "unnest", "field" => "nums", "value_key" => "n" }],
        [{ "id" => 1, "nums" => [10] }]
      )
      expect(result).to eq([{ "id" => 1, "n" => 10 }])
    end

    it "passes a record through unchanged when the field is not an Array" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1, "items" => "not-an-array" }]
      )
      expect(result).to eq([{ "id" => 1, "items" => "not-an-array" }])
    end

    it "passes a record through unchanged when the field is absent" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1 }]
      )
      expect(result).to eq([{ "id" => 1 }])
    end

    it "is a no-op (passthrough) when no 'field' is configured" do
      result = transform([{ "op" => "unnest" }], [{ "id" => 1, "items" => [1, 2] }])
      expect(result).to eq([{ "id" => 1, "items" => [1, 2] }])
    end

    it "resolves the field via a symbol key on the record" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ id: 1, items: [{ "sku" => "a" }] }]
      )
      expect(result).to eq([{ "id" => 1, "sku" => "a" }])
    end

    it "passes non-Hash records straight through" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        ["raw", { "items" => [1] }]
      )
      expect(result).to eq(["raw", { "value" => 1 }])
    end

    it "produces an empty list of children for an empty array element list" do
      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1, "items" => [] }]
      )
      expect(result).to eq([])
    end

    it "caps total output at MAX_RECORDS and drops the overflow" do
      stub_const("Ai::DataSources::TransformService::MAX_RECORDS", 3)

      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [{ "id" => 1, "items" => [1, 2, 3, 4, 5, 6, 7, 8] }]
      )

      expect(result.size).to be <= 3
      expect(result.size).to eq(3)
    end

    it "caps passthrough records too (the cap gates every emit)" do
      stub_const("Ai::DataSources::TransformService::MAX_RECORDS", 2)

      # Five passthrough records (field absent) — only MAX_RECORDS survive.
      records = Array.new(5) { |i| { "id" => i } }
      result = transform([{ "op" => "unnest", "field" => "items" }], records)

      expect(result.size).to eq(2)
    end

    it "stops cleanly across multiple records once the cap is reached" do
      stub_const("Ai::DataSources::TransformService::MAX_RECORDS", 3)

      result = transform(
        [{ "op" => "unnest", "field" => "items" }],
        [
          { "id" => 1, "items" => [1, 2] },
          { "id" => 2, "items" => [3, 4] },
          { "id" => 3, "items" => [5, 6] }
        ]
      )
      expect(result.size).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # SELECT / PROJECT
  # ---------------------------------------------------------------------------
  describe "select / project" do
    let(:records) { [{ "a" => 1, "b" => 2, "c" => 3 }] }

    it "keeps only the listed 'fields'" do
      result = transform([{ "op" => "select", "fields" => %w[a c] }], records)
      expect(result).to eq([{ "a" => 1, "c" => 3 }])
    end

    it "supports the 'project' alias" do
      result = transform([{ "op" => "project", "fields" => ["b"] }], records)
      expect(result).to eq([{ "b" => 2 }])
    end

    it "removes the listed 'drop' keys" do
      result = transform([{ "op" => "select", "drop" => ["b"] }], records)
      expect(result).to eq([{ "a" => 1, "c" => 3 }])
    end

    it "lets 'fields' WIN when both 'fields' and 'drop' are given" do
      result = transform(
        [{ "op" => "select", "fields" => ["a"], "drop" => ["a"] }],
        records
      )
      expect(result).to eq([{ "a" => 1 }])
    end

    it "passes through unchanged when neither 'fields' nor 'drop' is given" do
      result = transform([{ "op" => "select" }], records)
      expect(result).to eq(records)
    end

    it "omits requested fields that are absent from the record" do
      result = transform([{ "op" => "select", "fields" => %w[a missing] }], records)
      expect(result).to eq([{ "a" => 1 }])
    end

    it "matches fields against stringified symbol keys" do
      result = transform([{ "op" => "select", "fields" => ["a"] }], [{ a: 1, b: 2 }])
      expect(result).to eq([{ "a" => 1 }])
    end

    it "passes non-Hash records through unchanged on keep" do
      result = transform([{ "op" => "select", "fields" => ["a"] }], ["raw", { "a" => 1 }])
      expect(result).to eq(["raw", { "a" => 1 }])
    end

    it "preserves a nil field value that is present in the record" do
      result = transform([{ "op" => "select", "fields" => ["a"] }], [{ "a" => nil }])
      expect(result).to eq([{ "a" => nil }])
    end
  end

  # ---------------------------------------------------------------------------
  # RENAME
  # ---------------------------------------------------------------------------
  describe "rename" do
    it "renames matching keys, leaving others untouched" do
      result = transform(
        [{ "op" => "rename", "map" => { "old" => "new" } }],
        [{ "old" => 1, "keep" => 2 }]
      )
      expect(result).to eq([{ "new" => 1, "keep" => 2 }])
    end

    it "renames multiple keys at once" do
      result = transform(
        [{ "op" => "rename", "map" => { "a" => "x", "b" => "y" } }],
        [{ "a" => 1, "b" => 2 }]
      )
      expect(result).to eq([{ "x" => 1, "y" => 2 }])
    end

    it "is a passthrough when 'map' is not a Hash" do
      result = transform(
        [{ "op" => "rename", "map" => "nope" }],
        [{ "a" => 1 }]
      )
      expect(result).to eq([{ "a" => 1 }])
    end

    it "is a passthrough when 'map' is an empty Hash" do
      result = transform([{ "op" => "rename", "map" => {} }], [{ "a" => 1 }])
      expect(result).to eq([{ "a" => 1 }])
    end

    it "stringifies record keys it does not rename" do
      result = transform(
        [{ "op" => "rename", "map" => { "a" => "x" } }],
        [{ a: 1, b: 2 }]
      )
      expect(result).to eq([{ "x" => 1, "b" => 2 }])
    end

    it "coerces non-string map targets to strings" do
      result = transform(
        [{ "op" => "rename", "map" => { "a" => :renamed } }],
        [{ "a" => 1 }]
      )
      expect(result).to eq([{ "renamed" => 1 }])
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — concat / coalesce
  # ---------------------------------------------------------------------------
  describe "computed: concat" do
    it "joins fields with no separator by default" do
      result = transform(
        [computed_step("concat", as: "full", fields: %w[first last])],
        [{ "first" => "Jane", "last" => "Doe" }]
      )
      expect(result.first["full"]).to eq("JaneDoe")
    end

    it "joins fields with the configured separator" do
      result = transform(
        [computed_step("concat", as: "full", fields: %w[first last], separator: " ")],
        [{ "first" => "Jane", "last" => "Doe" }]
      )
      expect(result.first["full"]).to eq("Jane Doe")
    end

    it "stringifies non-string and nil operands ('' for nil)" do
      result = transform(
        [computed_step("concat", as: "j", fields: %w[a b c], separator: "-")],
        [{ "a" => 1, "b" => nil, "c" => true }]
      )
      expect(result.first["j"]).to eq("1--true")
    end
  end

  describe "computed: coalesce" do
    it "returns the first present (non-nil/non-blank) field" do
      result = transform(
        [computed_step("coalesce", as: "v", fields: %w[a b c])],
        [{ "a" => nil, "b" => "", "c" => "found" }]
      )
      expect(result.first["v"]).to eq("found")
    end

    it "skips an empty array but returns a present scalar" do
      result = transform(
        [computed_step("coalesce", as: "v", fields: %w[a b])],
        [{ "a" => [], "b" => 5 }]
      )
      expect(result.first["v"]).to eq(5)
    end

    it "yields nil when every candidate is blank" do
      result = transform(
        [computed_step("coalesce", as: "v", fields: %w[a b])],
        [{ "a" => nil, "b" => "" }]
      )
      expect(result.first["v"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — arithmetic
  # ---------------------------------------------------------------------------
  describe "computed: arithmetic" do
    it "adds two operands from 'a'/'b'" do
      result = transform(
        [computed_step("+", as: "sum", a: "x", b: "y")],
        [{ "x" => 2, "y" => 3 }]
      )
      expect(result.first["sum"]).to eq(5)
    end

    it "subtracts operands taken from the first two 'fields'" do
      result = transform(
        [computed_step("-", as: "d", fields: %w[x y])],
        [{ "x" => 10, "y" => 4 }]
      )
      expect(result.first["d"]).to eq(6)
    end

    it "multiplies two operands" do
      result = transform(
        [computed_step("*", as: "p", a: "x", b: "y")],
        [{ "x" => 6, "y" => 7 }]
      )
      expect(result.first["p"]).to eq(42)
    end

    it "divides two operands" do
      result = transform(
        [computed_step("/", as: "q", a: "x", b: "y")],
        [{ "x" => 20, "y" => 4 }]
      )
      expect(result.first["q"]).to eq(5)
    end

    it "coerces numeric STRINGS to numbers before computing" do
      result = transform(
        [computed_step("+", as: "sum", a: "x", b: "y")],
        [{ "x" => "2.5", "y" => "1.5" }]
      )
      expect(result.first["sum"]).to eq(4.0)
    end

    it "returns nil on divide-by-zero" do
      result = transform(
        [computed_step("/", as: "q", a: "x", b: "y")],
        [{ "x" => 10, "y" => 0 }]
      )
      expect(result.first["q"]).to be_nil
    end

    it "returns nil when an operand is non-numeric" do
      result = transform(
        [computed_step("+", as: "sum", a: "x", b: "y")],
        [{ "x" => "abc", "y" => 3 }]
      )
      expect(result.first["sum"]).to be_nil
    end

    it "returns nil when an operand is missing" do
      result = transform(
        [computed_step("*", as: "p", a: "x", b: "y")],
        [{ "x" => 4 }]
      )
      expect(result.first["p"]).to be_nil
    end

    it "returns nil for a non-finite (overflow) result like 1e308 * 1e308" do
      result = transform(
        [computed_step("*", as: "p", a: "x", b: "y")],
        [{ "x" => "1e308", "y" => "1e308" }]
      )
      expect(result.first["p"]).to be_nil
    end

    it "returns nil for an Infinity-producing division of huge floats" do
      # 1e308 / 1e-308 overflows to Infinity -> dropped to nil.
      result = transform(
        [computed_step("/", as: "q", a: "x", b: "y")],
        [{ "x" => "1e308", "y" => "1e-308" }]
      )
      expect(result.first["q"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — string ops
  # ---------------------------------------------------------------------------
  describe "computed: string ops (upcase / downcase / strip)" do
    it "upcases a string field" do
      result = transform(
        [computed_step("upcase", as: "u", field: "name")],
        [{ "name" => "jane" }]
      )
      expect(result.first["u"]).to eq("JANE")
    end

    it "downcases a string field" do
      result = transform(
        [computed_step("downcase", as: "d", field: "name")],
        [{ "name" => "JANE" }]
      )
      expect(result.first["d"]).to eq("jane")
    end

    it "strips a string field" do
      result = transform(
        [computed_step("strip", as: "s", field: "name")],
        [{ "name" => "  jane  " }]
      )
      expect(result.first["s"]).to eq("jane")
    end

    it "returns nil for upcase on a non-string value" do
      result = transform(
        [computed_step("upcase", as: "u", field: "n")],
        [{ "n" => 42 }]
      )
      expect(result.first["u"]).to be_nil
    end

    it "returns nil when the string-op 'field' is missing config" do
      result = transform([computed_step("downcase", as: "d")], [{ "name" => "x" }])
      expect(result.first["d"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — substring / slice
  # ---------------------------------------------------------------------------
  describe "computed: substring / slice" do
    it "extracts a substring with start + length" do
      result = transform(
        [computed_step("substring", as: "s", field: "name", start: 0, length: 3)],
        [{ "name" => "powernode" }]
      )
      expect(result.first["s"]).to eq("pow")
    end

    it "supports the 'slice' alias" do
      result = transform(
        [computed_step("slice", as: "s", field: "name", start: 1, length: 2)],
        [{ "name" => "abcd" }]
      )
      expect(result.first["s"]).to eq("bc")
    end

    it "extracts from 'start' to end when no length is given" do
      result = transform(
        [computed_step("substring", as: "s", field: "name", start: 4)],
        [{ "name" => "powernode" }]
      )
      expect(result.first["s"]).to eq("rnode")
    end

    it "tolerates a negative start (Ruby-style indexing)" do
      result = transform(
        [computed_step("substring", as: "s", field: "name", start: -3)],
        [{ "name" => "powernode" }]
      )
      expect(result.first["s"]).to eq("ode")
    end

    it "tolerates an out-of-range start (returns nil from String#[])" do
      result = transform(
        [computed_step("substring", as: "s", field: "name", start: 100, length: 3)],
        [{ "name" => "short" }]
      )
      expect(result.first["s"]).to be_nil
    end

    it "returns nil for a non-string field" do
      result = transform(
        [computed_step("substring", as: "s", field: "n", start: 0, length: 1)],
        [{ "n" => 12_345 }]
      )
      expect(result.first["s"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — template / format
  # ---------------------------------------------------------------------------
  describe "computed: template / format" do
    it "interpolates {field} tokens with record values" do
      result = transform(
        [computed_step("template", as: "label", template: "{a}-{b}")],
        [{ "a" => "x", "b" => "y" }]
      )
      expect(result.first["label"]).to eq("x-y")
    end

    it "supports the 'format' alias" do
      result = transform(
        [computed_step("format", as: "label", template: "[{a}]")],
        [{ "a" => "hi" }]
      )
      expect(result.first["label"]).to eq("[hi]")
    end

    it "substitutes '' for a missing field token" do
      result = transform(
        [computed_step("template", as: "label", template: "{a}-{missing}-{b}")],
        [{ "a" => "x", "b" => "z" }]
      )
      expect(result.first["label"]).to eq("x--z")
    end

    it "trims whitespace inside the token before lookup" do
      result = transform(
        [computed_step("template", as: "label", template: "{ a }")],
        [{ "a" => "hi" }]
      )
      expect(result.first["label"]).to eq("hi")
    end

    it "returns nil when 'template' is not a String" do
      result = transform(
        [computed_step("template", as: "label", template: 123)],
        [{ "a" => "x" }]
      )
      expect(result.first["label"]).to be_nil
    end

    it "stringifies non-string interpolated values" do
      result = transform(
        [computed_step("template", as: "label", template: "n={n}")],
        [{ "n" => 7 }]
      )
      expect(result.first["label"]).to eq("n=7")
    end
  end

  # ---------------------------------------------------------------------------
  # COMPUTED — general behavior
  # ---------------------------------------------------------------------------
  describe "computed: general" do
    it "is a passthrough when no 'as' field is configured" do
      result = transform([{ "op" => "computed", "fn" => "concat", "fields" => ["a"] }], [{ "a" => "x" }])
      expect(result).to eq([{ "a" => "x" }])
    end

    it "writes the computed field onto each record (deterministic presence)" do
      result = transform(
        [computed_step("upcase", as: "u", field: "name")],
        [{ "name" => "jane" }, { "name" => "bob" }]
      )
      expect(result.map { |r| r["u"] }).to eq(%w[JANE BOB])
    end

    it "always writes the 'as' field, as nil, when the value is not computable" do
      # upcase on a non-string -> nil, but the key MUST be present.
      result = transform(
        [computed_step("upcase", as: "u", field: "n")],
        [{ "n" => 42 }]
      )
      expect(result.first).to have_key("u")
      expect(result.first["u"]).to be_nil
    end

    it "reads the inner op from 'operation' as a fallback" do
      result = transform(
        [{ "op" => "computed", "operation" => "concat", "as" => "j", "fields" => %w[a b], "separator" => "/" }],
        [{ "a" => "x", "b" => "y" }]
      )
      expect(result.first["j"]).to eq("x/y")
    end

    it "reads the inner op from 'compute' as a fallback" do
      result = transform(
        [{ "op" => "computed", "compute" => "upcase", "as" => "u", "field" => "name" }],
        [{ "name" => "jane" }]
      )
      expect(result.first["u"]).to eq("JANE")
    end
  end

  # ---------------------------------------------------------------------------
  # SECURITY: dangerous computed op names are NEVER executed
  # ---------------------------------------------------------------------------
  describe "SECURITY: computed op whitelist" do
    # Each of these op tokens names a dangerous Ruby/Kernel method. The computed
    # interpreter dispatches through an EXPLICIT case statement; an unrecognized
    # op falls into the else branch -> nil, with NO method ever invoked.
    %w[system eval send public_send instance_eval class_eval exit exit! fork
       constantize `system` `eval` open require load __send__ define_method
       to_proc instance_variable_set].each do |dangerous|
      it "treats #{dangerous.inspect} as UNKNOWN: writes nil, never executes" do
        result = nil
        expect do
          result = transform(
            [computed_step(dangerous, as: "out", field: "cmd", fields: %w[cmd], a: "cmd", b: "cmd",
                                      template: "{cmd}", start: 0, length: 1)],
            [{ "cmd" => "echo pwned" }]
          )
        end.not_to raise_error

        # The 'as' field is present but nil — the op was a no-op.
        expect(result.first).to have_key("out")
        expect(result.first["out"]).to be_nil
        # The original field is untouched (proves nothing mutated the record state).
        expect(result.first["cmd"]).to eq("echo pwned")
      end
    end

    it "does not invoke Kernel#system for a 'system' op (no side effect)" do
      # Belt-and-suspenders: assert via public API only that the value is nil and
      # the source field is intact. No metaprogramming, no method spies — the
      # explicit case statement guarantees no dispatch.
      result = transform(
        [computed_step("system", as: "out", field: "cmd")],
        [{ "cmd" => "touch /tmp/powernode_transform_pwned_#{SecureRandom.hex(4)}" }]
      )
      expect(result.first["out"]).to be_nil
    end

    it "treats a 'send' op as unknown even when 'field' names a real method-like value" do
      result = transform(
        [computed_step("send", as: "out", field: "to_s")],
        [{ "to_s" => "value" }]
      )
      expect(result.first["out"]).to be_nil
    end

    it "treats mixed-case dangerous op names as unknown (downcased, still unmatched)" do
      result = transform(
        [computed_step("SYSTEM", as: "out", field: "cmd")],
        [{ "cmd" => "x" }]
      )
      expect(result.first["out"]).to be_nil
    end

    it "treats an empty inner op as unknown (nil result)" do
      result = transform(
        [{ "op" => "computed", "fn" => "", "as" => "out" }],
        [{ "a" => 1 }]
      )
      expect(result.first["out"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown TOP-LEVEL op
  # ---------------------------------------------------------------------------
  describe "unknown top-level op" do
    it "is a no-op (records unchanged) for an unrecognized op" do
      result = transform([{ "op" => "frobnicate" }], [{ "a" => 1 }])
      expect(result).to eq([{ "a" => 1 }])
    end

    it "is a no-op for a dangerous top-level op name (never executed)" do
      result = nil
      expect do
        result = transform([{ "op" => "system", "cmd" => "echo pwned" }], [{ "a" => 1 }])
      end.not_to raise_error
      expect(result).to eq([{ "a" => 1 }])
    end

    it "is a no-op for a step with no 'op' key at all" do
      result = transform([{ "fields" => ["a"] }], [{ "a" => 1, "b" => 2 }])
      expect(result).to eq([{ "a" => 1, "b" => 2 }])
    end

    it "skips an unknown op but still runs surrounding valid steps" do
      result = transform(
        [
          { "op" => "select", "fields" => %w[a b] },
          { "op" => "bogus" },
          { "op" => "rename", "map" => { "a" => "x" } }
        ],
        [{ "a" => 1, "b" => 2, "c" => 3 }]
      )
      expect(result).to eq([{ "x" => 1, "b" => 2 }])
    end
  end

  # ---------------------------------------------------------------------------
  # PIPELINE ORDER & COMPOSITION
  # ---------------------------------------------------------------------------
  describe "pipeline order and composition" do
    it "composes a computed step feeding a later select" do
      result = transform(
        [
          computed_step("concat", as: "full", fields: %w[first last], separator: " "),
          { "op" => "select", "fields" => ["full"] }
        ],
        [{ "first" => "Jane", "last" => "Doe" }]
      )
      expect(result).to eq([{ "full" => "Jane Doe" }])
    end

    it "composes an unnest (changes count) followed by a flatten on each record" do
      result = transform(
        [
          { "op" => "unnest", "field" => "items" },
          { "op" => "flatten" }
        ],
        [
          {
            "id" => 1,
            "items" => [
              { "meta" => { "k" => "v1" } },
              { "meta" => { "k" => "v2" } }
            ]
          }
        ]
      )
      expect(result).to eq([
                             { "id" => 1, "meta.k" => "v1" },
                             { "id" => 1, "meta.k" => "v2" }
                           ])
    end

    it "applies steps strictly in order (rename then select sees renamed keys)" do
      result = transform(
        [
          { "op" => "rename", "map" => { "a" => "x" } },
          { "op" => "select", "fields" => ["x"] }
        ],
        [{ "a" => 1, "b" => 2 }]
      )
      expect(result).to eq([{ "x" => 1 }])
    end

    it "order matters: select-before-rename drops the field rename would target" do
      result = transform(
        [
          { "op" => "select", "fields" => ["b"] },
          { "op" => "rename", "map" => { "a" => "x" } }
        ],
        [{ "a" => 1, "b" => 2 }]
      )
      # 'a' was dropped before rename, so rename is a no-op on 'a'.
      expect(result).to eq([{ "b" => 2 }])
    end

    it "chains arithmetic then template using the computed field" do
      result = transform(
        [
          computed_step("+", as: "sum", a: "x", b: "y"),
          computed_step("template", as: "label", template: "total={sum}")
        ],
        [{ "x" => 2, "y" => 3 }]
      )
      expect(result.first["label"]).to eq("total=5")
    end

    it "caps the pipeline length at MAX_PIPELINE_STEPS, running only the first N" do
      stub_const("Ai::DataSources::TransformService::MAX_PIPELINE_STEPS", 2)

      # Three rename steps; only the first two should run.
      result = transform(
        [
          { "op" => "rename", "map" => { "a" => "b" } },
          { "op" => "rename", "map" => { "b" => "c" } },
          { "op" => "rename", "map" => { "c" => "d" } }
        ],
        [{ "a" => 1 }]
      )
      # a -> b -> c, then the 3rd (c -> d) is dropped, so key stays "c".
      expect(result).to eq([{ "c" => 1 }])
    end

    it "honors the cap even when later (dropped) steps would change the result" do
      stub_const("Ai::DataSources::TransformService::MAX_PIPELINE_STEPS", 1)

      result = transform(
        [
          { "op" => "select", "fields" => %w[a b] },
          { "op" => "select", "fields" => ["a"] }
        ],
        [{ "a" => 1, "b" => 2, "c" => 3 }]
      )
      # Only the first select runs.
      expect(result).to eq([{ "a" => 1, "b" => 2 }])
    end
  end

  # ---------------------------------------------------------------------------
  # RESILIENCE: malformed steps are skipped, #apply never raises
  # ---------------------------------------------------------------------------
  describe "resilience" do
    it "skips a flatten step whose 'only' is not an array, never raising" do
      result = nil
      expect do
        result = transform([{ "op" => "flatten", "only" => "notanarray" }], [{ "a" => { "b" => 1 } }])
      end.not_to raise_error
      # "notanarray" coerces via string_list to ["notanarray"]; "a" is not in it,
      # so it is NOT descended -> record passes through unchanged.
      expect(result).to eq([{ "a" => { "b" => 1 } }])
    end

    it "skips a computed step missing 'as' (passthrough), never raising" do
      result = nil
      expect do
        result = transform([{ "op" => "computed" }], [{ "a" => 1 }])
      end.not_to raise_error
      expect(result).to eq([{ "a" => 1 }])
    end

    it "never raises and returns best-effort records on a chain with a bad step" do
      result = nil
      expect do
        result = transform(
          [
            { "op" => "select", "fields" => ["a"] },
            { "op" => "computed" },          # malformed -> skipped
            { "op" => "rename", "map" => 5 } # malformed map -> passthrough
          ],
          [{ "a" => 1, "b" => 2 }]
        )
      end.not_to raise_error
      expect(result).to eq([{ "a" => 1 }])
    end

    it "tolerates a step that is not a Hash (filtered out of the pipeline)" do
      result = nil
      expect do
        result = described_class.new("pipeline" => ["junk", 42, { "op" => "select", "fields" => ["a"] }])
                                .apply([{ "a" => 1, "b" => 2 }])
      end.not_to raise_error
      expect(result).to eq([{ "a" => 1 }])
    end

    it "tolerates entirely empty step hashes (treated as unknown op)" do
      result = transform([{}], [{ "a" => 1 }])
      expect(result).to eq([{ "a" => 1 }])
    end

    it "tolerates a records array mixing hashes and scalars across a full pipeline" do
      result = nil
      expect do
        result = transform(
          [
            { "op" => "rename", "map" => { "a" => "x" } },
            { "op" => "select", "fields" => ["x"] }
          ],
          [{ "a" => 1 }, "scalar", nil, 99]
        )
      end.not_to raise_error
      expect(result).to eq([{ "x" => 1 }, "scalar", nil, 99])
    end

    it "does not raise when records is a non-Array (coerced) with a real pipeline" do
      result = nil
      expect do
        result = described_class.new("pipeline" => [{ "op" => "select", "fields" => ["a"] }])
                                .apply({ "a" => 1, "b" => 2 })
      end.not_to raise_error
      expect(result).to eq([{ "a" => 1 }])
    end
  end
end
