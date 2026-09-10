# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Runbook::Registry do
  before { described_class.reset! }
  after  { described_class.reset! }

  # A fake catalog with the same #for contract the system extension's
  # System::Runbooks::Catalog exposes: an entry hash for a known kind, nil for
  # an unknown one. Core must never name that class, so the spec proves the
  # seam over a fake rather than over the real one.
  # NOTE the signature: no keyword arguments. With one, Ruby would parse a
  # trailing bare hash at the call site as keywords and `map` would arrive
  # empty — every example would then pass or fail for a reason that has
  # nothing to do with the registry.
  def source(map)
    src = Object.new
    src.define_singleton_method(:for) { |kind| map[kind.to_s] }
    src
  end

  describe ".register_source" do
    it "refuses an object that cannot answer #for" do
      expect { described_class.register_source(Object.new) }
        .to raise_error(ArgumentError, /must respond to #for/)
    end

    it "resolves an entry a source claims" do
      described_class.register_source(source("a.kind" => { "doc" => "docs/runbooks/a.md#top" }))

      expect(described_class.for("a.kind")).to eq("doc" => "docs/runbooks/a.md#top")
    end

    it "does not register the same source twice" do
      src = source("a.kind" => { "doc" => "docs/runbooks/a.md#top" })
      described_class.register_source(src)
      described_class.register_source(src)

      expect(described_class.registered_sources.size).to eq(1)
    end

    it "hands out a frozen copy of its sources" do
      described_class.register_source(source({}))

      expect(described_class.registered_sources).to be_frozen
    end
  end

  describe "resolution order" do
    it "walks sources in registration order and the first non-nil wins" do
      described_class.register_source(source("a.kind" => { "doc" => "first.md#x" }))
      described_class.register_source(source("a.kind" => { "doc" => "second.md#x" }))

      expect(described_class.for("a.kind")).to eq("doc" => "first.md#x")
    end

    it "falls through a declining source to a later one" do
      described_class.register_source(source({}))
      described_class.register_source(source("a.kind" => { "doc" => "second.md#x" }))

      expect(described_class.for("a.kind")).to eq("doc" => "second.md#x")
    end

    # Ownership: whoever emits the kind owns the mapping, so a catalog that
    # has an opinion beats core's fallback.
    it "prefers a source's entry over a core-registered one" do
      described_class.register("a.kind", generator: "Core::Generator", args: { x: 1 })
      described_class.register_source(source("a.kind" => { "doc" => "extension.md#x" }))

      expect(described_class.for("a.kind")).to eq("doc" => "extension.md#x")
    end

    it "uses the core-registered entry when no source claims the kind" do
      described_class.register("core.only", generator: "Core::Generator", args: { x: 1 })
      described_class.register_source(source({}))

      expect(described_class.for("core.only")).to eq("generator" => "Core::Generator", "args" => { x: 1 })
    end
  end

  describe ".register" do
    it "refuses a blank kind" do
      expect { described_class.register("  ", doc: "a.md#b") }.to raise_error(ArgumentError, /must be present/)
    end

    it "refuses an entry with no recognised key" do
      expect { described_class.register("a.kind", nonsense: true) }
        .to raise_error(ArgumentError, /at least one of/)
    end

    # A typo'd key must not travel as opaque payload some renderer later
    # treats as truth.
    it "drops unrecognised keys from an otherwise valid entry" do
      described_class.register("a.kind", doc: "a.md#b", not_documeted: true)

      expect(described_class.for("a.kind")).to eq("doc" => "a.md#b")
    end

    it "unregisters" do
      described_class.register("a.kind", doc: "a.md#b")

      expect(described_class.unregister("a.kind")).to eq("doc" => "a.md#b")
      expect(described_class.for("a.kind")).to be_nil
    end
  end

  describe ".render" do
    it "splits a doc entry into path and anchor" do
      described_class.register_source(source("a.kind" => { "doc" => "docs/runbooks/a.md#phase-4--run-" }))

      expect(described_class.render("a.kind")).to eq(
        kind: "doc", doc: "docs/runbooks/a.md#phase-4--run-",
        path: "docs/runbooks/a.md", anchor: "phase-4--run-"
      )
    end

    it "leaves the anchor nil for a doc entry with none" do
      described_class.register_source(source("a.kind" => { "doc" => "docs/runbooks/a.md" }))

      expect(described_class.render("a.kind")).to include(path: "docs/runbooks/a.md", anchor: nil)
    end

    it "renders a generator entry" do
      described_class.register("a.kind", generator: "Ai::Executors::Something", args: { limit: 5 })

      expect(described_class.render("a.kind")).to eq(
        kind: "generator", generator: "Ai::Executors::Something", args: { limit: 5 }
      )
    end

    it "defaults a generator's args to an empty hash rather than nil" do
      described_class.register("a.kind", generator: "Ai::Executors::Something")

      expect(described_class.render("a.kind")[:args]).to eq({})
    end

    # "Nobody has decided" and "decided, and there is nothing to point at"
    # are DIFFERENT answers. Collapsing them turns a coverage gap into a
    # closed question.
    describe "the two shapes of 'none'" do
      it "marks a deliberately undocumented kind as known, with its reason" do
        described_class.register_source(
          source("a.kind" => { "not_documented" => true, "reason" => "the fix is a one-liner in the manifest" })
        )

        expect(described_class.render("a.kind")).to eq(
          kind: "none", known: true, reason: "the fix is a one-liner in the manifest"
        )
      end

      it "marks an unregistered kind as NOT known" do
        expect(described_class.render("never.seen")).to eq(
          kind: "none", known: false, reason: "NotRegistered"
        )
      end

      it "keeps the two apart" do
        described_class.register_source(source("decided.kind" => { "not_documented" => true, "reason" => "n/a" }))

        decided = described_class.render("decided.kind")
        unknown = described_class.render("undecided.kind")

        expect(decided[:known]).to be true
        expect(unknown[:known]).to be false
        expect(decided).not_to eq(unknown)
      end
    end
  end

  describe "a raising source" do
    it "is logged and skipped rather than taking down the lookup" do
      exploding = Object.new
      exploding.define_singleton_method(:for) { |_kind| raise "catalog will not parse" }
      described_class.register_source(exploding)
      described_class.register_source(source("a.kind" => { "doc" => "survivor.md#x" }))

      expect(Rails.logger).to receive(:error).with(/raised for a.kind/)
      expect(described_class.for("a.kind")).to eq("doc" => "survivor.md#x")
    end
  end

  describe ".documented?" do
    it "is true for a doc entry and false for an undocumented one" do
      described_class.register_source(
        source("has.doc" => { "doc" => "a.md#b" },
               "no.doc" => { "not_documented" => true, "reason" => "n/a" })
      )

      expect(described_class.documented?("has.doc")).to be true
      expect(described_class.documented?("no.doc")).to be false
      expect(described_class.documented?("unknown.kind")).to be false
    end
  end
end
