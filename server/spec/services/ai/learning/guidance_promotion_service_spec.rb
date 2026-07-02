# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::GuidancePromotionService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account: account) }

  before do
    # Embeddings are best-effort; stub so promotion + search never make a real call
    # (search then falls back to keyword match, which still increments usage_count).
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate_batch).and_return([])
  end

  def guidance_entry(slug)
    Ai::SharedKnowledge
      .where(account: account)
      .where("provenance->>'guidance_key' = ?", "guidance:#{slug}")
      .first
  end

  describe "#promote (upsert-by guidance_key)" do
    it "creates a guidance-* tagged, account-scoped reference entry from content" do
      result = service.promote(
        slug: "escalation-governance",
        title: "Escalation Governance",
        content: "Escalation rationale MUST be built at classify time.",
        tags: ["escalation"]
      )

      expect(result).to be_promoted
      expect(result.outcome).to eq(:created)

      entry = guidance_entry("escalation-governance")
      expect(entry.title).to eq("Escalation Governance")
      expect(entry.content_type).to eq("reference")
      expect(entry.access_level).to eq("account")
      expect(entry.tags).to include("guidance", "guidance-escalation-governance", "escalation")
    end

    it "is idempotent — re-promoting the same slug UPDATES in place, never duplicates" do
      service.promote(slug: "escalation-governance", content: "v1 rule text")

      expect do
        r = service.promote(slug: "escalation-governance", content: "v2 rule text, revised")
        expect(r.outcome).to eq(:updated)
      end.not_to change { Ai::SharedKnowledge.where(account: account).count }

      expect(guidance_entry("escalation-governance").content).to eq("v2 rule text, revised")
    end

    it "no-ops (unchanged) when re-promoting byte-identical content" do
      service.promote(slug: "g", content: "same content")
      expect(service.promote(slug: "g", content: "same content").outcome).to eq(:unchanged)
    end

    it "promotes an existing CompoundLearning, stamps promoted_at, and back-links the source" do
      learning = create(:ai_compound_learning, account: account,
                        title: "Reuse completion callbacks",
                        content: "Outcome feedback loops should reuse existing after_update callbacks.",
                        category: "best_practice")

      result = service.promote(slug: "reuse-callbacks", learning: learning)

      expect(result).to be_promoted
      expect(learning.reload.promoted_at).to be_present
      entry = guidance_entry("reuse-callbacks")
      expect(entry.title).to eq("Reuse completion callbacks")
      expect(entry.provenance["source_learning_id"]).to eq(learning.id)
    end

    it "refuses content that structurally names a private extension (gate #9)" do
      result = described_class.new(account: account, private_names: ["acme"])
                              .promote(slug: "leaky", content: "Call Acme::Service from the extension.")

      expect(result).to be_refused
      expect(guidance_entry("leaky")).to be_nil
    end

    it "skips blank slug or content" do
      expect(service.promote(slug: "", content: "x").outcome).to eq(:skipped)
      expect(service.promote(slug: "x", content: "").outcome).to eq(:skipped)
    end
  end

  describe "verified injection — consumption end-to-end" do
    # This is the exact path inc8 will use: promote the escalation-governance rule,
    # then retrieve it through the SAME tag-query path the search_knowledge tool /
    # dev_next_task digest use, and confirm the consumption counter advances.
    it "a promoted entry is retrievable via the guidance tag-query path and advances usage_count" do
      service.promote(
        slug: "escalation-governance",
        title: "Escalation Governance",
        content: "Escalation rationale must be built at classify time; hold one-rung effort jumps below the score bar."
      )
      entry = guidance_entry("escalation-governance")
      expect(entry.usage_count).to eq(0)

      knowledge = Ai::Memory::SharedKnowledgeService.new(account: account)
      result = knowledge.search(
        query: "escalation governance rationale",
        tags: ["guidance-escalation-governance"]
      )

      expect(result[:success]).to be(true)
      expect(result[:entries].map { |e| e[:id] }).to include(entry.id)
      # touch_usage! during search is the real consumption counter for this store.
      expect(entry.reload.usage_count).to be >= 1
    end
  end
end
