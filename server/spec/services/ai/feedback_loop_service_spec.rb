# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FeedbackLoopService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  # Create an unapplied feedback with an explicit creation order so the batch
  # selection is deterministic (oldest first).
  def create_feedback(rating:, created_at:)
    Ai::AgentFeedback.create!(
      account: account,
      user: user,
      ai_agent_id: agent.id,
      feedback_type: "execution_quality",
      rating: rating,
      created_at: created_at,
      updated_at: created_at
    )
  end

  describe '#apply_feedback_to_trust' do
    let!(:trust_score) do
      create(:ai_agent_trust_score, account: account, agent: agent, overall_score: 0.5)
    end

    context 'with more unapplied feedbacks than the batch size' do
      # 25 unapplied: the oldest 20 (the batch) all rate 5; the newest 5 rate 1.
      # If average() and update_all() operated on different row sets (the old
      # non-atomic, unordered bug), the delta applied to trust would not match
      # the rows that get marked applied.
      before do
        base = 10.days.ago
        # Oldest 20 — the batch that MUST be processed (rating 5 each)
        20.times { |i| create_feedback(rating: 5, created_at: base + i.minutes) }
        # Newest 5 — must remain unapplied (rating 1 each)
        5.times { |i| create_feedback(rating: 1, created_at: base + (100 + i).minutes) }
      end

      it 'averages exactly the rows it marks applied (deterministic batch)' do
        applied_ids_before = Ai::AgentFeedback.for_agent(agent.id)
                                              .where(applied_to_trust: true).pluck(:id)
        expect(applied_ids_before).to be_empty

        result = service.apply_feedback_to_trust(agent)

        applied = Ai::AgentFeedback.for_agent(agent.id).where(applied_to_trust: true)
        unapplied = Ai::AgentFeedback.for_agent(agent.id).unapplied

        # Exactly the batch size was applied, the remainder untouched.
        expect(applied.count).to eq(20)
        expect(unapplied.count).to eq(5)

        # The applied rows are precisely the all-5 batch; the avg the service
        # used to move trust must be the avg of exactly those applied rows.
        expect(applied.pluck(:rating).uniq).to eq([5])
        expect(unapplied.pluck(:rating).uniq).to eq([1])

        # avg of applied rows = 5.0 → quality_delta = (5-3)/2 = 1.0
        expect(result[:quality_delta]).to eq(1.0)
        expect(result[:feedbacks_applied]).to eq(20)

        # trust moved by quality_delta * 0.1 = +0.1 → 0.6
        expect(trust_score.reload.overall_score).to be_within(1e-9).of(0.6)
      end
    end

    context 'when called twice with two full batches available' do
      before do
        base = 10.days.ago
        # First batch (oldest 20): rating 5
        20.times { |i| create_feedback(rating: 5, created_at: base + i.minutes) }
        # Second batch (next 20): rating 1
        20.times { |i| create_feedback(rating: 1, created_at: base + (100 + i).minutes) }
      end

      it 'processes the NEXT batch on the second call, never double-counting the first' do
        first = service.apply_feedback_to_trust(agent)
        # First batch averages 5.0
        expect(first[:quality_delta]).to eq(1.0)
        expect(first[:feedbacks_applied]).to eq(20)
        expect(Ai::AgentFeedback.for_agent(agent.id).unapplied.count).to eq(20)

        second = service.apply_feedback_to_trust(agent)
        # Second batch averages 1.0 → quality_delta = (1-3)/2 = -1.0
        # (would be 1.0 again if the same rows were re-processed)
        expect(second[:quality_delta]).to eq(-1.0)
        expect(second[:feedbacks_applied]).to eq(20)

        # Everything applied exactly once.
        expect(Ai::AgentFeedback.for_agent(agent.id).unapplied.count).to eq(0)
        expect(Ai::AgentFeedback.for_agent(agent.id).where(applied_to_trust: true).count).to eq(40)
      end
    end

    context 'when there are no unapplied feedbacks' do
      it 'returns without touching trust' do
        expect(service.apply_feedback_to_trust(agent)).to be_nil
      end
    end
  end

  # F4: suggestion `type` strings are a closed contract with
  # Api::V1::Internal::Ai::AutonomyController#analyze_policy_patterns, which
  # switches on suggestion[:type] via `==` comparisons rather than an
  # exhaustive case and always files the result as recommendation_type
  # "agent_reliability". Nothing validated that only the two known type
  # strings ever reach that controller — a future third type would silently
  # fall through the controller's ternaries instead of failing loudly. Route
  # every suggestion through a guard that drops (and logs) anything outside
  # the known set.
  describe '#build_suggestion (suggestion type guard)' do
    it 'builds a suggestion for a known type' do
      result = service.send(:build_suggestion, type: 'quality_concern', message: 'x', agent_id: agent.id, approval_rate: 0.2)

      expect(result).to eq(type: 'quality_concern', message: 'x', agent_id: agent.id, approval_rate: 0.2)
    end

    it 'drops and logs an unrecognized suggestion type instead of forwarding it' do
      expect(Rails.logger).to receive(:warn).with(/unrecognized.*mystery_type/i)

      result = service.send(:build_suggestion, type: 'mystery_type', message: 'x', agent_id: agent.id, approval_rate: 0.5)

      expect(result).to be_nil
    end
  end
end
