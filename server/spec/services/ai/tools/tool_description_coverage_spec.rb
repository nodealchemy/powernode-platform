# frozen_string_literal: true

require "rails_helper"

# Tool-description ratchet (Phase 6 of the 2026-09-25 prompt audit): every
# advertised action states purpose in a listing-sized sentence 1 and carries a
# contract. The backlog is a frozen snapshot that may only shrink; the rules
# live in spec/support/tool_description_coverage.rb.
RSpec.describe "MCP tool description coverage ratchet" do
  subject(:report) { ToolDescriptionCoverage.report }

  it "has no new under-described action" do
    expect(report[:growth]).to be_empty, lambda {
      "#{report[:growth].size} action(s) are under-described and not in " \
        "#{ToolDescriptionCoverage::SNAPSHOT_PATH}:\n  #{report[:growth].join("\n  ")}\n\n" \
        "Lead with a purpose sentence of at most 160 chars and state the contract " \
        "(3+ sentences, or declare_action limit:/paginated:/returns:/refuses:/see_also:)."
    }
  end

  it "keeps no stale entry: a listed action that now passes must leave the snapshot" do
    expect(report[:rot]).to be_empty, lambda {
      "Remove these now-passing (or removed) actions from #{ToolDescriptionCoverage::SNAPSHOT_PATH}:\n  " +
        report[:rot].join("\n  ")
    }
  end

  describe "the rules (synthetic descriptions)" do
    def defects(text, contract: false) = ToolDescriptionCoverage.defects(text, contract_declared: contract)

    it "passes a listing-sized purpose sentence followed by a contract" do
      expect(defects("List agents. Returns at most 50. Refuses nothing.")).to be_empty
      expect(defects("List agents.", contract: true)).to be_empty
    end

    it "fails a one-liner with no contract metadata" do
      expect(defects("List agents.")).to include(/fewer than 3 sentences/)
    end

    it "fails a first sentence over the listing budget" do
      expect(defects("#{'x' * 161}. Two. Three.")).to include(/over 160/)
    end

    it "fails a first sentence that leaves a parenthesis open" do
      expect(defects("Fetch a Cve (by id. Two. Three.")).to include(/open/)
    end

    it "reports growth and rot in both directions" do
      descs = { "a_ok" => "Do a. Two. Three.", "b_bad" => "Do b." }
      allow(ToolDescriptionCoverage).to receive(:contract_declared?).and_return(false)

      expect(ToolDescriptionCoverage.report(descs, [])).to eq(growth: [ "b_bad" ], rot: [])
      expect(ToolDescriptionCoverage.report(descs, %w[a_ok b_bad])).to eq(growth: [], rot: [ "a_ok" ])
    end
  end
end
