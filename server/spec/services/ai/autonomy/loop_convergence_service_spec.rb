# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Autonomy::LoopConvergenceService do
  let(:account) { create(:account) }

  def create_offer(fingerprint:, created_at: Time.current, type: "convention_adherence", acct: account)
    create(:ai_improvement_recommendation,
           account: acct,
           recommendation_type: type,
           target_type: "Account",
           target_id: acct.id,
           evidence: { "fingerprint" => fingerprint, "title" => "spec offer" },
           created_at: created_at)
  end

  def create_class_learning(tag, created_at: Time.current, acct: account, status: "active")
    create(:ai_compound_learning, account: acct, tags: ["ralph_loop", tag], status: status, created_at: created_at)
  end

  describe ".compute" do
    it "returns the empty state when no improvements were surfaced in the window" do
      result = described_class.compute(account: account)

      expect(result[:window_days]).to eq(30)
      expect(result[:improvements_scanned]).to eq(0)
      expect(result[:surfaced_classes]).to eq(0)
      expect(result[:recurrent_classes]).to eq(0)
      expect(result[:recurrence_rate]).to be_nil
      expect(result[:classes]).to eq([])
    end

    it "counts a class as recurrent when its tag was learned before it resurfaced" do
      create_class_learning("class:server-worker-jobseam", created_at: 10.days.ago)
      create_offer(fingerprint: "convention_adherence|scripts/pattern-validation.sh|server-worker-jobseam-guard",
                   created_at: 2.days.ago)

      result = described_class.compute(account: account)

      expect(result[:improvements_scanned]).to eq(1)
      expect(result[:surfaced_classes]).to eq(1)
      expect(result[:recurrent_classes]).to eq(1)
      expect(result[:recurrence_rate]).to eq(1.0)
      expect(result[:classes]).to contain_exactly(
        hash_including(tag: "class:server-worker-jobseam", occurrences: 1, recurrent: true)
      )
    end

    it "matches an explicit class-tag fingerprint segment against prior learnings" do
      create_class_learning("class:n-plus-one", created_at: 5.days.ago)
      create_offer(fingerprint: "class:n-plus-one|server/app/models/foo.rb|bare-all-map", created_at: 1.day.ago)

      result = described_class.compute(account: account)

      expect(result[:recurrent_classes]).to eq(1)
      expect(result[:classes].first[:tag]).to eq("class:n-plus-one")
    end

    it "counts an explicitly class-tagged offer with no prior learning as novel (not recurrent)" do
      create_offer(fingerprint: "class:brand-new-class|server/app/foo.rb|detail", created_at: 1.day.ago)

      result = described_class.compute(account: account)

      expect(result[:surfaced_classes]).to eq(1)
      expect(result[:recurrent_classes]).to eq(0)
      expect(result[:recurrence_rate]).to eq(0.0)
      expect(result[:classes].first).to include(tag: "class:brand-new-class", recurrent: false)
    end

    it "does not count a class learned only after it surfaced" do
      create_offer(fingerprint: "class:late-learned|server/app/foo.rb|detail", created_at: 3.days.ago)
      create_class_learning("class:late-learned", created_at: 1.day.ago)

      result = described_class.compute(account: account)

      expect(result[:surfaced_classes]).to eq(1)
      expect(result[:recurrent_classes]).to eq(0)
    end

    it "ignores offers outside the window, non-code-quality types, and unclassifiable fingerprints" do
      create_class_learning("class:server-worker-jobseam", created_at: 90.days.ago)
      create_offer(fingerprint: "convention_adherence|x.rb|server-worker-jobseam-old", created_at: 60.days.ago)
      create_offer(fingerprint: "class:server-worker-jobseam|y.rb|z", type: "provider_switch", created_at: 1.day.ago)
      create_offer(fingerprint: "code_lint|server/app/foo.rb|totally-unrelated-detail", created_at: 1.day.ago)

      result = described_class.compute(account: account)

      expect(result[:improvements_scanned]).to eq(1)
      expect(result[:surfaced_classes]).to eq(0)
      expect(result[:recurrence_rate]).to be_nil
    end

    it "is scoped to the account: another account's learnings do not make a class recurrent" do
      other = create(:account)
      create_class_learning("class:cross-acct", created_at: 10.days.ago, acct: other)
      create_offer(fingerprint: "class:cross-acct|server/app/foo.rb|detail", created_at: 1.day.ago)

      result = described_class.compute(account: account)

      expect(result[:recurrent_classes]).to eq(0)
    end

    it "aggregates occurrences per class and honors a custom window" do
      create_class_learning("class:txn-atomicity", created_at: 20.days.ago)
      create_offer(fingerprint: "class:txn-atomicity|a.rb|one", created_at: 3.days.ago)
      create_offer(fingerprint: "class:txn-atomicity|b.rb|two", created_at: 2.days.ago)
      create_offer(fingerprint: "class:other-class|c.rb|three", created_at: 12.days.ago)

      result = described_class.compute(account: account, window_days: 7)

      expect(result[:window_days]).to eq(7)
      expect(result[:improvements_scanned]).to eq(2)
      expect(result[:surfaced_classes]).to eq(1)
      expect(result[:classes].first).to include(tag: "class:txn-atomicity", occurrences: 2, recurrent: true)
    end
  end
end
