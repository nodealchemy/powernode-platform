# frozen_string_literal: true

require "rails_helper"

# Regression: goal_progress / governance / stigmergic_signal sensors called
# Base#build_observation(title:, observation_type:, ..., expires_in:) with the
# unsupported kwargs `sensor_type:` and `expires_at:`, raising ArgumentError —
# and they never defined the abstract #sensor_type. ObservationPipelineService's
# safe_collect rescued+logged it, so these sensors silently produced ZERO
# observations on every triggering condition. Each must now define #sensor_type
# and emit observations through build_observation without raising.
RSpec.describe "Autonomy sensors emit observations via build_observation", type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  describe Ai::Autonomy::Sensors::GoalProgressSensor do
    subject(:sensor) { described_class.new(account: account, agent: agent) }

    it { expect(sensor.sensor_type).to eq("goal_progress") }

    it "emits an observation for a stale active goal (no ArgumentError)" do
      goal = Ai::AgentGoal.create!(
        account: account, agent: agent,
        title: "Stale goal", description: "x",
        goal_type: "creation", status: "active", priority: 3, progress: 0.0
      )
      goal.update_column(:updated_at, 25.hours.ago)

      observations = nil
      expect { observations = sensor.collect }.not_to raise_error
      expect(observations).to be_present
      expect(observations.first[:sensor_type]).to eq("goal_progress")
      expect(observations.first[:expires_at]).to be_a(Time)
    end
  end

  describe Ai::Autonomy::Sensors::GovernanceSensor do
    subject(:sensor) { described_class.new(account: account, agent: agent) }

    it { expect(sensor.sensor_type).to eq("governance") }

    it "emits an observation for an open critical report (no ArgumentError)" do
      Ai::GovernanceReport.create!(
        account: account, report_type: "anomaly", severity: "critical", status: "open"
      )

      observations = nil
      expect { observations = sensor.collect }.not_to raise_error
      expect(observations).to be_present
      expect(observations.first[:sensor_type]).to eq("governance")
      expect(observations.first[:expires_at]).to be_a(Time)
    end
  end

  describe Ai::Autonomy::Sensors::StigmergicSignalSensor do
    subject(:sensor) { described_class.new(account: account, agent: agent) }

    it { expect(sensor.sensor_type).to eq("stigmergic_signal") }

    it "emits an observation for a strong warning signal (no ArgumentError)" do
      Ai::StigmergicSignal.create!(
        account_id: account.id, signal_key: "alert-key",
        signal_type: "warning", strength: 0.8
      )

      observations = nil
      expect { observations = sensor.collect }.not_to raise_error
      expect(observations).to be_present
      expect(observations.first[:sensor_type]).to eq("stigmergic_signal")
      expect(observations.first[:expires_at]).to be_a(Time)
    end
  end
end
