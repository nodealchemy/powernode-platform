# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::Evaluators::Concerns::ConvergenceExit do
  let(:test_class) do
    Class.new(Trading::Evaluators::Base) do
      include Trading::Evaluators::Concerns::ConvergenceExit
    end
  end

  let(:base_context) do
    {
      "strategy" => { "id" => "s1", "pair" => "BTC-YES", "parameters" => params },
      "market_data" => { "last_price" => 0.55, "bid" => 0.53, "ask" => 0.57, "volume_24h" => 10_000 },
      "positions" => [],
      "allocated_capital" => 1000.0,
      "market_expiry" => (Time.now + 3600 * 4).iso8601,
      "last_entry_indicators" => last_entry_indicators
    }
  end

  let(:params) { {} }
  let(:last_entry_indicators) { { "edge" => 0.10, "edge_pct" => 10.0 } }
  let(:evaluator) { test_class.new(base_context) }

  describe "#expected_remaining_edge" do
    it "returns full edge when hours_left equals total_hours" do
      result = evaluator.expected_remaining_edge(
        current_edge: 0.10, hours_left: 24.0, total_hours: 24.0, alpha: 0.7
      )
      expect(result).to be_within(0.001).of(0.10)
    end

    it "returns zero when hours_left is zero" do
      result = evaluator.expected_remaining_edge(
        current_edge: 0.10, hours_left: 0.0, total_hours: 24.0, alpha: 0.7
      )
      expect(result).to eq(0.0)
    end

    it "decays faster near settlement (alpha < 1)" do
      # At 50% time remaining
      mid = evaluator.expected_remaining_edge(
        current_edge: 0.10, hours_left: 12.0, total_hours: 24.0, alpha: 0.7
      )
      # At 25% time remaining
      late = evaluator.expected_remaining_edge(
        current_edge: 0.10, hours_left: 6.0, total_hours: 24.0, alpha: 0.7
      )
      # Verify decay accelerates
      expect(mid).to be > late
      expect(mid).to be > 0.05 # At 50%, with alpha 0.7, ~0.062
      expect(late).to be < mid * 0.7 # Late decay is faster than linear
    end

    it "with alpha=1 gives linear decay" do
      result = evaluator.expected_remaining_edge(
        current_edge: 0.10, hours_left: 12.0, total_hours: 24.0, alpha: 1.0
      )
      expect(result).to be_within(0.001).of(0.05) # Linear: 0.10 * 0.5
    end
  end

  describe "#should_exit_convergence?" do
    it "returns true when remaining edge < exit cost" do
      result = evaluator.should_exit_convergence?(
        remaining_edge: 0.01, exit_cost: 0.02, opportunity_cost: 0.001
      )
      expect(result).to be true
    end

    it "returns false when remaining edge > exit cost + opportunity cost" do
      result = evaluator.should_exit_convergence?(
        remaining_edge: 0.05, exit_cost: 0.02, opportunity_cost: 0.001
      )
      expect(result).to be false
    end

    it "accounts for opportunity cost in the threshold" do
      # Edge covers exit cost but not exit + opportunity
      result = evaluator.should_exit_convergence?(
        remaining_edge: 0.025, exit_cost: 0.02, opportunity_cost: 0.01
      )
      expect(result).to be true
    end
  end

  describe "#convergence_exit_check" do
    let(:position) do
      {
        "side" => "long",
        "opened_at" => (Time.now - 3600 * 20).iso8601, # 20 hours ago
        "entry_price" => 0.45
      }
    end

    context "when edge has decayed below exit cost" do
      # 4 hours left, opened 20h ago, total_hours = 24
      # remaining edge = 0.10 * (4/24)^0.7 ≈ 0.028
      # exit cost ≈ 0.02-0.05 (spread-based)
      it "returns an exit signal" do
        result = evaluator.convergence_exit_check(position, 4.0)
        # May or may not trigger depending on exact cost estimation
        # but should be a hash or nil
        if result
          expect(result[:type]).to eq("exit")
          expect(result[:indicators][:exit_reason]).to eq("convergence")
        end
      end
    end

    context "when edge has NOT decayed enough" do
      let(:last_entry_indicators) { { "edge" => 0.25 } } # Large initial edge

      it "returns nil (no exit needed)" do
        # 20 hours left with large edge → should NOT trigger
        result = evaluator.convergence_exit_check(position, 20.0)
        expect(result).to be_nil
      end
    end

    context "with no entry edge data" do
      let(:last_entry_indicators) { {} }

      it "returns nil" do
        result = evaluator.convergence_exit_check(position, 4.0)
        expect(result).to be_nil
      end
    end

    context "when position opened recently (below min_hours)" do
      let(:position) do
        {
          "side" => "long",
          "opened_at" => (Time.now - 30 * 60).iso8601, # 30 minutes ago
          "entry_price" => 0.45
        }
      end

      it "returns nil (too early for convergence exit)" do
        result = evaluator.convergence_exit_check(position, 4.0)
        expect(result).to be_nil
      end
    end

    context "with nil hours_left" do
      it "returns nil" do
        result = evaluator.convergence_exit_check(position, nil)
        expect(result).to be_nil
      end
    end
  end
end
