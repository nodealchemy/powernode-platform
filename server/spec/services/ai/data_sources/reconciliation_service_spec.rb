# frozen_string_literal: true

require "rails_helper"

# Phase 4b-3c multi-source long-tail. Ai::DataSources::ReconciliationService is the
# deterministic "canonical-key merge" half: it collapses N independent record sets
# (Array<Array<Hash>>) returned by the fetch path into ONE Array<Hash> by EXACT
# (string-coerced) match on a configured key field, per a fixed strategy.
#
# This is a PURE, STATELESS service — plain Ruby hashes in, plain hashes out, no DB,
# no network, no embeddings, no clock. So there are no factories and no stubbed
# collaborators here; the only external touch is Rails.logger (warn on cap / unknown
# strategy, error on internal fault), which a few examples assert against.
#
# The behaviors under test, drawn straight from the service's documented contract:
#   * first_wins / last_wins (default) / merge collapse strategies
#   * merge with MIXED string/symbol key spellings collapses to ONE key (no dup field)
#   * Integer-vs-String key value coercion: 1 and "1" reconcile to the same group
#   * stable FIRST-APPEARANCE output ordering regardless of strategy
#   * keyless records pass through FLAGGED ("_unreconciled"), never dropped, never collide
#   * inputs are NEVER mutated
#   * unknown strategy degrades to last_wins (does not raise)
#   * MAX_OUTPUT cap on NEW distinct keys / keyless rows (updates to admitted keys still apply)
#   * empty / nil / blank inputs => []
#   * EXACT key match only — NO fuzzy / entity resolution ("Acme" != "ACME")
RSpec.describe Ai::DataSources::ReconciliationService, type: :service do
  # Default service keys on "id" with the default strategy (last_wins).
  subject(:service) { described_class.new(key: "id") }

  describe "#reconcile empty / nil / blank inputs" do
    it "returns [] for nil input" do
      expect(service.reconcile(nil)).to eq([])
    end

    it "returns [] for an empty array of sets" do
      expect(service.reconcile([])).to eq([])
    end

    it "returns [] when every set is empty" do
      expect(service.reconcile([[], [], []])).to eq([])
    end

    it "returns [] when the only set contains nothing reconcilable" do
      # blank? is true for [] but not for [[]]; an all-empty inner set still yields []
      expect(service.reconcile([[]])).to eq([])
    end
  end

  describe "#reconcile defensive skipping of malformed elements" do
    it "skips non-Array sets without raising" do
      sets = [nil, "not-a-set", 42, [{ "id" => "1", "v" => "a" }]]
      result = service.reconcile(sets)
      expect(result).to eq([{ "id" => "1", "v" => "a" }])
    end

    it "skips non-Hash records inside a set without raising" do
      sets = [[nil, "x", 7, { "id" => "1", "v" => "a" }, %w[also not a hash]]]
      result = service.reconcile(sets)
      expect(result).to eq([{ "id" => "1", "v" => "a" }])
    end

    it "returns [] when sets contain only malformed elements" do
      expect(service.reconcile([[nil, "x", 1], ["y", 2]])).to eq([])
    end
  end

  describe "strategy: first_wins" do
    subject(:service) { described_class.new(key: "id", strategy: "first_wins") }

    it "keeps the FIRST record seen for a key and discards later duplicates" do
      sets = [
        [{ "id" => "1", "v" => "first" }],
        [{ "id" => "1", "v" => "second" }],
        [{ "id" => "1", "v" => "third" }]
      ]
      expect(service.reconcile(sets)).to eq([{ "id" => "1", "v" => "first" }])
    end

    it "ignores fields present only on later duplicates" do
      sets = [
        [{ "id" => "1", "a" => 1 }],
        [{ "id" => "1", "b" => 2 }]
      ]
      result = service.reconcile(sets)
      expect(result).to eq([{ "id" => "1", "a" => 1 }])
      expect(result.first).not_to have_key("b")
    end

    it "keeps distinct keys independent" do
      sets = [
        [{ "id" => "1", "v" => "x" }, { "id" => "2", "v" => "y" }],
        [{ "id" => "1", "v" => "X" }, { "id" => "2", "v" => "Y" }]
      ]
      expect(service.reconcile(sets)).to eq(
        [{ "id" => "1", "v" => "x" }, { "id" => "2", "v" => "y" }]
      )
    end
  end

  describe "strategy: last_wins (default)" do
    it "is the default strategy when none is supplied" do
      sets = [
        [{ "id" => "1", "v" => "first" }],
        [{ "id" => "1", "v" => "last" }]
      ]
      # default subject keys on id with no strategy arg
      expect(service.reconcile(sets)).to eq([{ "id" => "1", "v" => "last" }])
    end

    it "wholly REPLACES the prior winner (does not merge fields)" do
      sets = [
        [{ "id" => "1", "a" => 1, "b" => 2 }],
        [{ "id" => "1", "a" => 9 }]
      ]
      result = service.reconcile(sets)
      # b from the earlier record is gone — last record replaces wholesale
      expect(result).to eq([{ "id" => "1", "a" => 9 }])
      expect(result.first).not_to have_key("b")
    end

    it "honors an explicit last_wins strategy string" do
      svc = described_class.new(key: "id", strategy: "last_wins")
      sets = [[{ "id" => "1", "v" => "a" }], [{ "id" => "1", "v" => "z" }]]
      expect(svc.reconcile(sets)).to eq([{ "id" => "1", "v" => "z" }])
    end
  end

  describe "strategy: merge" do
    subject(:service) { described_class.new(key: "id", strategy: "merge") }

    it "overlays later NON-NIL fields onto the first record (later non-nil wins)" do
      sets = [
        [{ "id" => "1", "a" => 1, "b" => 2 }],
        [{ "id" => "1", "b" => 20, "c" => 30 }]
      ]
      expect(service.reconcile(sets)).to eq(
        [{ "id" => "1", "a" => 1, "b" => 20, "c" => 30 }]
      )
    end

    it "keeps the earlier value where the later record's field is nil" do
      sets = [
        [{ "id" => "1", "a" => 1, "b" => 2 }],
        [{ "id" => "1", "b" => nil, "c" => 3 }]
      ]
      result = service.reconcile(sets)
      # b stays 2 because incoming b is nil; c is added
      expect(result).to eq([{ "id" => "1", "a" => 1, "b" => 2, "c" => 3 }])
    end

    it "replaces a nested Hash value wholesale (one level deep only)" do
      sets = [
        [{ "id" => "1", "meta" => { "x" => 1, "y" => 2 } }],
        [{ "id" => "1", "meta" => { "x" => 9 } }]
      ]
      result = service.reconcile(sets)
      # NOT deep-merged: meta is replaced entirely, so y disappears
      expect(result).to eq([{ "id" => "1", "meta" => { "x" => 9 } }])
    end

    it "merges across THREE sightings cumulatively" do
      sets = [
        [{ "id" => "1", "a" => 1 }],
        [{ "id" => "1", "b" => 2 }],
        [{ "id" => "1", "c" => 3 }]
      ]
      expect(service.reconcile(sets)).to eq(
        [{ "id" => "1", "a" => 1, "b" => 2, "c" => 3 }]
      )
    end

    it "treats an explicit nil-valued first field as overridable by a later non-nil" do
      sets = [
        [{ "id" => "1", "a" => nil }],
        [{ "id" => "1", "a" => 5 }]
      ]
      expect(service.reconcile(sets)).to eq([{ "id" => "1", "a" => 5 }])
    end
  end

  describe "merge with MIXED string/symbol key spellings (the stringify fix)" do
    subject(:service) { described_class.new(key: "id", strategy: "merge") }

    it "collapses a field spelled :name in one source and \"name\" in another to ONE key" do
      sets = [
        [{ "id" => "1", :name => "old", "kept" => true }],
        [{ "id" => "1", "name" => "new" }]
      ]
      result = service.reconcile(sets).first

      # The merged record must NOT carry both :name and "name" — exactly one entry.
      name_keys = result.keys.select { |k| k.to_s == "name" }
      expect(name_keys.size).to eq(1)
      # And the later non-nil value wins.
      expect(result["name"] || result[:name]).to eq("new")
    end

    it "produces a fully String-keyed merged record (both sides stringified)" do
      sets = [
        [{ id: "1", a: 1 }],
        [{ "id" => "1", "b" => 2 }]
      ]
      result = service.reconcile(sets).first
      expect(result.keys).to all(be_a(String))
      expect(result).to eq({ "id" => "1", "a" => 1, "b" => 2 })
    end

    it "does not duplicate the key field itself when spellings differ across sets" do
      sets = [
        [{ id: "1", "v" => "a" }],
        [{ "id" => "1", :w => "b" }]
      ]
      result = service.reconcile(sets).first
      id_keys = result.keys.select { |k| k.to_s == "id" }
      expect(id_keys.size).to eq(1)
    end

    it "collapses three differently-spelled sightings of one field to a single entry" do
      sets = [
        [{ "id" => "1", :status => "a" }],
        [{ "id" => "1", "status" => "b" }],
        [{ "id" => "1", :status => "c" }]
      ]
      result = service.reconcile(sets).first
      status_keys = result.keys.select { |k| k.to_s == "status" }
      expect(status_keys.size).to eq(1)
      expect(result["status"] || result[:status]).to eq("c")
    end
  end

  describe "key value coercion: Integer vs String reconcile (exact string form)" do
    it "reconciles Integer 1 and String \"1\" into the same group (last_wins)" do
      sets = [
        [{ "id" => 1, "v" => "int-keyed" }],
        [{ "id" => "1", "v" => "string-keyed" }]
      ]
      result = service.reconcile(sets)
      # One slot — both records share canonical key "1"; last wins.
      expect(result.size).to eq(1)
      expect(result.first["v"]).to eq("string-keyed")
    end

    it "reconciles Integer and String key values under first_wins too" do
      svc = described_class.new(key: "id", strategy: "first_wins")
      sets = [
        [{ "id" => 1, "v" => "int" }],
        [{ "id" => "1", "v" => "str" }]
      ]
      result = svc.reconcile(sets)
      expect(result.size).to eq(1)
      expect(result.first["v"]).to eq("int")
    end

    it "groups Integer key sightings across sets together" do
      sets = [
        [{ "id" => 7, "v" => "a" }],
        [{ "id" => 7, "v" => "b" }]
      ]
      expect(service.reconcile(sets).size).to eq(1)
    end

    it "treats an empty-string key value as a REAL, distinct key (not keyless)" do
      sets = [[{ "id" => "", "v" => "blank-key" }]]
      result = service.reconcile(sets)
      expect(result.size).to eq(1)
      # A real key => NOT flagged as unreconciled
      expect(result.first).not_to have_key(described_class::UNRECONCILED_FLAG)
      expect(result.first["v"]).to eq("blank-key")
    end

    it "groups two empty-string-keyed records together (exact match on \"\")" do
      sets = [
        [{ "id" => "", "v" => "a" }],
        [{ "id" => "", "v" => "b" }]
      ]
      # last_wins => one slot, last value
      result = service.reconcile(sets)
      expect(result.size).to eq(1)
      expect(result.first["v"]).to eq("b")
    end
  end

  describe "EXACT key match only — NO fuzzy / entity resolution" do
    it "treats \"Acme\" and \"ACME\" as DIFFERENT keys (case-sensitive)" do
      svc = described_class.new(key: "name")
      sets = [[{ "name" => "Acme", "v" => 1 }, { "name" => "ACME", "v" => 2 }]]
      result = svc.reconcile(sets)
      expect(result.size).to eq(2)
    end

    it "does not collapse values that differ only by surrounding whitespace" do
      svc = described_class.new(key: "name")
      sets = [[{ "name" => "Acme" }, { "name" => " Acme " }]]
      expect(svc.reconcile(sets).size).to eq(2)
    end

    it "does not collapse near-identical numeric strings (\"1\" vs \"1.0\")" do
      sets = [[{ "id" => "1", "v" => "a" }, { "id" => "1.0", "v" => "b" }]]
      expect(service.reconcile(sets).size).to eq(2)
    end
  end

  describe "stable first-appearance ordering (independent of strategy)" do
    it "keeps the last_wins winner in the key's ORIGINAL slot (not moved to the end)" do
      sets = [
        [{ "id" => "a", "v" => 1 }, { "id" => "b", "v" => 2 }, { "id" => "c", "v" => 3 }],
        [{ "id" => "a", "v" => 99 }]
      ]
      result = service.reconcile(sets)
      # 'a' updated to 99 but still first; b, c hold their original order.
      expect(result.map { |r| r["id"] }).to eq(%w[a b c])
      expect(result.first["v"]).to eq(99)
    end

    it "fixes each distinct key's slot at its FIRST appearance under merge" do
      svc = described_class.new(key: "id", strategy: "merge")
      sets = [
        [{ "id" => "x", "n" => 1 }, { "id" => "y", "n" => 2 }],
        [{ "id" => "y", "extra" => true }, { "id" => "z", "n" => 3 }]
      ]
      result = svc.reconcile(sets)
      expect(result.map { |r| r["id"] }).to eq(%w[x y z])
    end

    it "preserves first-appearance order under first_wins" do
      svc = described_class.new(key: "id", strategy: "first_wins")
      sets = [
        [{ "id" => "3" }, { "id" => "1" }, { "id" => "2" }],
        [{ "id" => "1" }, { "id" => "3" }]
      ]
      expect(svc.reconcile(sets).map { |r| r["id"] }).to eq(%w[3 1 2])
    end

    it "interleaves keyless pass-throughs in their own first-appearance slots" do
      sets = [
        [{ "id" => "a", "v" => 1 }, { "noid" => "k1" }, { "id" => "b", "v" => 2 }],
        [{ "noid" => "k2" }, { "id" => "a", "v" => 11 }]
      ]
      result = service.reconcile(sets)
      # Order: a (slot0), keyless k1 (slot1), b (slot2), keyless k2 (slot3).
      # 'a' updates in place at slot0.
      expect(result.size).to eq(4)
      expect(result[0]["id"]).to eq("a")
      expect(result[0]["v"]).to eq(11)
      expect(result[1]["noid"]).to eq("k1")
      expect(result[2]["id"]).to eq("b")
      expect(result[3]["noid"]).to eq("k2")
    end
  end

  describe "keyless records: flagged pass-through, never dropped, never collide" do
    it "flags a keyless record with the UNRECONCILED_FLAG (String-keyed record)" do
      sets = [[{ "noid" => "x", "v" => 1 }]]
      result = service.reconcile(sets)
      expect(result.size).to eq(1)
      expect(result.first[described_class::UNRECONCILED_FLAG]).to be(true)
    end

    it "uses the constant value \"_unreconciled\" as the flag name" do
      expect(described_class::UNRECONCILED_FLAG).to eq("_unreconciled")
    end

    it "treats a record with a nil key VALUE as keyless (flagged)" do
      sets = [[{ "id" => nil, "v" => "no-key" }]]
      result = service.reconcile(sets)
      expect(result.first).to have_key(described_class::UNRECONCILED_FLAG)
      expect(result.first["v"]).to eq("no-key")
    end

    it "does NOT collide multiple keyless records together (each kept separately)" do
      sets = [[{ "a" => 1 }, { "b" => 2 }, { "c" => 3 }]]
      result = service.reconcile(sets)
      expect(result.size).to eq(3)
      expect(result).to all(have_key(described_class::UNRECONCILED_FLAG))
    end

    it "flags a symbol-keyed keyless record with a SYMBOL flag" do
      sets = [[{ noid: "x", v: 1 }]]
      result = service.reconcile(sets)
      expect(result.first).to have_key(described_class::UNRECONCILED_FLAG.to_sym)
      expect(result.first[described_class::UNRECONCILED_FLAG.to_sym]).to be(true)
    end

    it "flags a mixed-key keyless record with a STRING flag (jsonb-canonical default)" do
      sets = [[{ :sym => 1, "str" => 2 }]]
      result = service.reconcile(sets)
      # Mixed => String flag, not symbol
      expect(result.first).to have_key(described_class::UNRECONCILED_FLAG)
      expect(result.first).not_to have_key(described_class::UNRECONCILED_FLAG.to_sym)
    end

    it "keeps keyless pass-throughs alongside reconciled keyed records" do
      sets = [
        [{ "id" => "1", "v" => "keyed" }, { "loose" => true }]
      ]
      result = service.reconcile(sets)
      expect(result.size).to eq(2)
      keyed = result.find { |r| r["id"] == "1" }
      loose = result.find { |r| r.key?(described_class::UNRECONCILED_FLAG) }
      expect(keyed).not_to have_key(described_class::UNRECONCILED_FLAG)
      expect(loose["loose"]).to be(true)
    end
  end

  describe "key lookup is String/Symbol tolerant on the configured key field" do
    it "finds the key when the record carries it under a Symbol while service key is a String" do
      sets = [
        [{ id: "1", "v" => "sym-key-record" }],
        [{ "id" => "1", "v" => "str-key-record" }]
      ]
      # Both should be recognized as keyed on "1" and reconcile (last_wins).
      result = service.reconcile(sets)
      expect(result.size).to eq(1)
      expect(result.first["v"]).to eq("str-key-record")
    end

    it "accepts a Symbol key arg at construction (normalized via to_s)" do
      svc = described_class.new(key: :id)
      sets = [[{ "id" => "1", "v" => "a" }], [{ "id" => "1", "v" => "b" }]]
      expect(svc.reconcile(sets).size).to eq(1)
    end
  end

  describe "inputs are NEVER mutated (purity)" do
    it "does not mutate the input hashes under last_wins" do
      r1 = { "id" => "1", "v" => "a" }
      r2 = { "id" => "1", "v" => "b" }
      sets = [[r1], [r2]]
      service.reconcile(sets)
      expect(r1).to eq({ "id" => "1", "v" => "a" })
      expect(r2).to eq({ "id" => "1", "v" => "b" })
    end

    it "does not mutate the input hashes under merge" do
      svc = described_class.new(key: "id", strategy: "merge")
      r1 = { "id" => "1", "a" => 1 }
      r2 = { "id" => "1", "b" => 2 }
      sets = [[r1], [r2]]
      svc.reconcile(sets)
      expect(r1).to eq({ "id" => "1", "a" => 1 })
      expect(r2).to eq({ "id" => "1", "b" => 2 })
    end

    it "does not mutate the input record when flagging a keyless pass-through" do
      r = { "noid" => "x" }
      service.reconcile([[r]])
      expect(r).to eq({ "noid" => "x" })
      expect(r).not_to have_key(described_class::UNRECONCILED_FLAG)
    end

    it "does not mutate the input array of sets" do
      sets = [[{ "id" => "1" }], [{ "id" => "1" }]]
      original = sets.map { |s| s.map(&:dup) }
      service.reconcile(sets)
      expect(sets).to eq(original)
    end

    it "returns hashes that are independent objects from the inputs (first_wins)" do
      svc = described_class.new(key: "id", strategy: "first_wins")
      r1 = { "id" => "1", "v" => "a" }
      result = svc.reconcile([[r1]])
      expect(result.first).not_to be(r1)
      # Mutating the output must not touch the input.
      result.first["v"] = "changed"
      expect(r1["v"]).to eq("a")
    end
  end

  describe "unknown / invalid strategy degrades to last_wins" do
    it "falls back to last_wins for an unrecognized strategy string" do
      allow(Rails.logger).to receive(:warn)
      svc = described_class.new(key: "id", strategy: "bogus")
      sets = [[{ "id" => "1", "v" => "first" }], [{ "id" => "1", "v" => "last" }]]
      expect(svc.reconcile(sets)).to eq([{ "id" => "1", "v" => "last" }])
    end

    it "logs a warning when given an unknown strategy" do
      expect(Rails.logger).to receive(:warn).with(/unknown strategy/)
      described_class.new(key: "id", strategy: "nonsense")
    end

    it "normalizes strategy case/whitespace (\" Merge \" => merge)" do
      svc = described_class.new(key: "id", strategy: " Merge ")
      sets = [
        [{ "id" => "1", "a" => 1 }],
        [{ "id" => "1", "b" => 2 }]
      ]
      # If normalized to merge, fields combine; if it had fallen back to last_wins,
      # 'a' would be gone.
      expect(svc.reconcile(sets)).to eq([{ "id" => "1", "a" => 1, "b" => 2 }])
    end

    it "does not warn when a valid strategy is supplied" do
      expect(Rails.logger).not_to receive(:warn)
      described_class.new(key: "id", strategy: "first_wins")
    end

    it "degrades a nil-ish strategy to the default without raising" do
      expect { described_class.new(key: "id", strategy: "") }.not_to raise_error
      svc = described_class.new(key: "id", strategy: "")
      sets = [[{ "id" => "1", "v" => "a" }], [{ "id" => "1", "v" => "b" }]]
      # Empty string is not a valid strategy => last_wins
      expect(svc.reconcile(sets)).to eq([{ "id" => "1", "v" => "b" }])
    end
  end

  describe "MAX_OUTPUT cap" do
    it "stops admitting NEW distinct keys once the cap is reached" do
      stub_const("#{described_class}::MAX_OUTPUT", 3)
      allow(Rails.logger).to receive(:warn)
      sets = [[
        { "id" => "1" }, { "id" => "2" }, { "id" => "3" }, { "id" => "4" }, { "id" => "5" }
      ]]
      result = service.reconcile(sets)
      expect(result.size).to eq(3)
      expect(result.map { |r| r["id"] }).to eq(%w[1 2 3])
    end

    it "stops admitting NEW keyless rows once the cap is reached" do
      stub_const("#{described_class}::MAX_OUTPUT", 2)
      allow(Rails.logger).to receive(:warn)
      sets = [[{ "a" => 1 }, { "b" => 2 }, { "c" => 3 }, { "d" => 4 }]]
      expect(service.reconcile(sets).size).to eq(2)
    end

    it "still honors UPDATES to an already-admitted key after the cap is hit" do
      stub_const("#{described_class}::MAX_OUTPUT", 2)
      allow(Rails.logger).to receive(:warn)
      sets = [
        [{ "id" => "1", "v" => "a" }, { "id" => "2", "v" => "b" }],
        # "3" is a NEW key beyond the cap => dropped; "1" is an update => applied
        [{ "id" => "3", "v" => "c" }, { "id" => "1", "v" => "A-updated" }]
      ]
      result = service.reconcile(sets)
      expect(result.size).to eq(2)
      one = result.find { |r| r["id"] == "1" }
      expect(one["v"]).to eq("A-updated")
      expect(result.map { |r| r["id"] }).not_to include("3")
    end

    it "logs a single capped warning when the cap drops records" do
      stub_const("#{described_class}::MAX_OUTPUT", 1)
      expect(Rails.logger).to receive(:warn).with(/output capped at 1 records/).once
      service.reconcile([[{ "id" => "1" }, { "id" => "2" }, { "id" => "3" }]])
    end

    it "does not log a capped warning when output stays under the cap" do
      stub_const("#{described_class}::MAX_OUTPUT", 100)
      expect(Rails.logger).not_to receive(:warn)
      service.reconcile([[{ "id" => "1" }, { "id" => "2" }]])
    end

    it "applies the cap across multiple sets (global, not per-set)" do
      stub_const("#{described_class}::MAX_OUTPUT", 2)
      allow(Rails.logger).to receive(:warn)
      sets = [
        [{ "id" => "1" }, { "id" => "2" }],
        [{ "id" => "3" }, { "id" => "4" }]
      ]
      result = service.reconcile(sets)
      expect(result.map { |r| r["id"] }).to eq(%w[1 2])
    end
  end

  describe "multi-set, multi-strategy integration" do
    it "reconciles overlapping sets from primary + mirror (last_wins)" do
      primary = [{ "id" => "1", "src" => "primary" }, { "id" => "2", "src" => "primary" }]
      mirror  = [{ "id" => "2", "src" => "mirror" }, { "id" => "3", "src" => "mirror" }]
      result = service.reconcile([primary, mirror])
      expect(result.map { |r| r["id"] }).to eq(%w[1 2 3])
      # id 2 last-won by the mirror set
      expect(result.find { |r| r["id"] == "2" }["src"]).to eq("mirror")
    end

    it "reconciles complementary feeds into enriched records (merge)" do
      svc = described_class.new(key: "isbn", strategy: "merge")
      catalog = [{ "isbn" => "978", "title" => "A Book" }]
      pricing = [{ "isbn" => "978", "price" => 9.99 }]
      result = svc.reconcile([catalog, pricing])
      expect(result).to eq([{ "isbn" => "978", "title" => "A Book", "price" => 9.99 }])
    end

    it "carries keyed reconciliation and keyless pass-through together across sets" do
      svc = described_class.new(key: "id", strategy: "merge")
      sets = [
        [{ "id" => "1", "a" => 1 }, { "anon" => "loose1" }],
        [{ "id" => "1", "b" => 2 }, { "anon" => "loose2" }]
      ]
      result = svc.reconcile(sets)
      merged = result.find { |r| r["id"] == "1" }
      expect(merged).to eq({ "id" => "1", "a" => 1, "b" => 2 })
      loose = result.select { |r| r.key?(described_class::UNRECONCILED_FLAG) }
      expect(loose.size).to eq(2)
    end
  end
end
