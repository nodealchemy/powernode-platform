# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — the confidence rule (design §5.3),
# stated so it can fail.
RSpec.describe Platform::Investigation::Confidence do
  def candidate(score, *classes)
    { score: score, evidence_classes: classes }
  end

  describe "the rule the design names" do
    # THE HEADLINE ARM. `attribute_failure` computes share-of-total and
    # therefore returns 1.0 for every single-candidate attribution by
    # construction. This rule must not.
    it "does NOT return 1.0 for one candidate supported by one class" do
      result = described_class.for([ candidate(10.0, "conditions") ])

      expect(result[:share]).to eq(1.0)
      expect(result[:value]).to be < 1.0
      expect(result[:value]).to eq(described_class::SINGLE_SOURCE_CEILING)
      expect(result[:state]).to eq(described_class::MEASURED)
    end

    it "splits two candidates proportionally" do
      results = described_class.for_each([
        candidate(6.0, "conditions", "status_events"),
        candidate(4.0, "conditions", "status_events")
      ])

      expect(results.map { |r| r[:share] }).to eq([ 0.6, 0.4 ])
      # The ratio survives the discount: 0.6/0.4 == 0.45/0.30.
      expect(results.map { |r| r[:value] }).to eq([ 0.45, 0.3 ])
      expect(results.map { |r| r[:ceiling] }).to eq([ nil, nil ])
    end

    it "returns not_measured, never 0.0, for an empty evidence set" do
      result = described_class.for([])

      expect(result[:state]).to eq(described_class::NOT_MEASURED)
      expect(result[:state]).to eq(Platform::ComponentStatus::NOT_MEASURED)
      expect(result[:value]).to be_nil
    end

    # The other arm of the same distinction: a candidate that WAS measured and
    # scored nothing is a finding, and it is not the same answer.
    it "distinguishes not_measured from a measured zero" do
      unmeasured = described_class.for([])
      measured_zero = described_class.for_each([
        candidate(0.0, "conditions"), candidate(5.0, "conditions")
      ]).first

      expect(unmeasured[:value]).to be_nil
      expect(measured_zero[:state]).to eq(described_class::MEASURED)
      expect(measured_zero[:value]).to eq(0.0)
    end
  end

  describe "the class discount" do
    it "closes half the remaining gap per independent class and never reaches 1.0" do
      factors = (1..4).map { |n| described_class.class_factor(n) }

      expect(factors).to eq([ 0.5, 0.75, 0.875, 0.9375 ])
      expect(factors.last).to be < 1.0
    end

    it "scores zero classes at zero" do
      expect(described_class.class_factor(0)).to eq(0.0)
      expect(described_class.class_factor(-1)).to eq(0.0)
    end

    it "raises a candidate's confidence when a second, independent class agrees" do
      one = described_class.for_each([ candidate(6.0, "conditions"), candidate(4.0, "conditions") ]).first
      two = described_class.for_each([
        candidate(6.0, "conditions", "module_changes"), candidate(4.0, "conditions")
      ]).first

      expect(two[:value]).to be > one[:value]
    end

    it "does not raise it for more items within ONE class" do
      # `evidence_classes` is a SET: naming the same class twice is one
      # observation, not two.
      once = described_class.for([ candidate(1.0, "conditions") ])
      twice = described_class.for([ candidate(1.0, "conditions", "conditions") ])

      expect(twice[:evidence_classes]).to eq(1)
      expect(twice[:value]).to eq(once[:value])
    end
  end

  describe "the single-candidate ceiling" do
    it "caps a lone candidate even when many classes agree" do
      result = described_class.for([ candidate(10.0, "a", "b", "c", "d") ])

      expect(result[:share]).to eq(1.0)
      expect(result[:ceiling]).to eq(described_class::SINGLE_CANDIDATE_CEILING)
      expect(result[:value]).to eq(described_class::SINGLE_CANDIDATE_CEILING)
    end

    it "applies no ceiling once a second candidate exists" do
      result = described_class.for([ candidate(9.0, "a", "b", "c", "d"), candidate(1.0, "a") ])

      expect(result[:ceiling]).to be_nil
      expect(result[:value]).to be > described_class::SINGLE_CANDIDATE_CEILING
    end

    it "uses the stricter ceiling for one candidate from one class" do
      expect(described_class::SINGLE_SOURCE_CEILING).to be < described_class::SINGLE_CANDIDATE_CEILING
      expect(described_class.for([ candidate(1.0, "a") ])[:ceiling])
        .to eq(described_class::SINGLE_SOURCE_CEILING)
    end
  end

  describe "#for_each" do
    it "scores every candidate by the same rule the winner is scored by" do
      candidates = [ candidate(6.0, "a", "b"), candidate(4.0, "a", "b") ]

      expect(described_class.for_each(candidates).first).to eq(described_class.for(candidates))
    end

    it "reports not_measured for every candidate when nothing is supported" do
      results = described_class.for_each([ candidate(0.0), candidate(0.0) ])

      expect(results.map { |r| r[:state] }).to all(eq(described_class::NOT_MEASURED))
    end
  end
end
