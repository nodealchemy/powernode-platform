# frozen_string_literal: true

require "rails_helper"

# Doc-tag → extension routing is declared by each extension in its extension.json
# ("knowledge_doc_tags") and resolved generically by the sync service. These specs cover
# the routing LOGIC with a stubbed route table (deterministic, env-independent); the real
# manifest scan is exercised end-to-end by the sync run in both modes.
RSpec.describe Ai::KnowledgeDocSyncService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  describe "#detect_extension (manifest-driven tag routing)" do
    before do
      allow(service).to receive(:tag_routes_pair).and_return([
        { "demoext" => "demoext", "billing" => "business", "baas" => "business" },
        { "venue:" => "demoext", "strategy:" => "demoext" }
      ])
    end

    it "routes an exact tag to its declaring extension" do
      expect(service.send(:detect_extension, [ "billing" ])).to eq("business")
      expect(service.send(:detect_extension, [ "demoext" ])).to eq("demoext")
    end

    it "routes a prefixed tag to its declaring extension" do
      expect(service.send(:detect_extension, [ "venue:kalshi" ])).to eq("demoext")
      expect(service.send(:detect_extension, [ "strategy:momentum" ])).to eq("demoext")
    end

    it "falls back to platform for unowned or blank tags" do
      expect(service.send(:detect_extension, [ "random" ])).to eq("platform")
      expect(service.send(:detect_extension, [])).to eq("platform")
      expect(service.send(:detect_extension, nil)).to eq("platform")
    end
  end

  describe "#tag_routes_pair (scans extension manifests generically)" do
    it "returns [exact_routes, prefix_routes] hashes built from manifests" do
      pair = service.send(:tag_routes_pair)

      expect(pair).to be_an(Array)
      expect(pair.size).to eq(2)
      expect(pair.first).to be_a(Hash)
      expect(pair.last).to be_a(Hash)
      # Every declared route value is a non-empty slug string.
      (pair.first.values + pair.last.values).each do |slug|
        expect(slug).to be_a(String)
        expect(slug).not_to be_empty
      end
    end
  end
end
